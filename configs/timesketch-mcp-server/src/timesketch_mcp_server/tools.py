from typing import Any

from .utils import get_timesketch_client
from timesketch_api_client import search
from collections import defaultdict
import pandas as pd

from fastmcp import FastMCP

mcp = FastMCP(name="timesketch-tools")

RESERVED_CHARS = [
    "+",
    "-",
    "=",
    "&&",
    "||",
    ">",
    "<",
    "!",
    "(",
    ")",
    "{",
    "}",
    "[",
    "]",
    "^",
    '"',
    "~",
    "*",
    "?",
    ":",
    "\\",
    "/",
]


def _run_field_bucket_aggregation(
    sketch: Any, field: str, limit: int = 10000
) -> list[dict[str, int]]:
    """
    Helper function to run a field bucket aggregation on a Timesketch sketch.

    Args:
        sketch: The Timesketch sketch object.
        field: The field to aggregate on.
        limit: The maximum number of buckets to return. Defaults to 10000.

    Returns:
        A list of dictionaries containing the field bucket aggregation results.
    """
    aggregation_result = sketch.run_aggregator(
        aggregator_name="field_bucket",
        aggregator_parameters={
            "field": field,
            "limit": limit,
        },
    )
    return aggregation_result.data.get("objects")[0]["field_bucket"]["buckets"]


@mcp.tool()
def discover_data_types(sketch_id: int) -> list[dict[str, int]]:
    """Discover data types in a Timesketch sketch.

    Args:
        sketch_id: The ID of the Timesketch sketch to discover data types from.

    Returns:
        A list of dictionaries containing data type information, including:
        - data_type: The name of the data type.
        - count: The number of events for that data type.
    """

    sketch = get_timesketch_client().get_sketch(sketch_id)
    return _run_field_bucket_aggregation(sketch, "data_type")


@mcp.tool()
def count_distinct_field_values(sketch_id: int, field: str) -> list[dict[str, int]]:
    """Runs an aggregation to count distinct values for the specified field.

    Args:
        sketch_id: The ID of the Timesketch sketch to run the aggregation on.
        field: The field to count distinct values for, eg. "data_type",
            "source_ip", "yara_match".

    Returns:
        A list of dictionaries containing the aggregation results.
    """

    sketch = get_timesketch_client().get_sketch(sketch_id)
    return _run_field_bucket_aggregation(sketch, field)


@mcp.tool()
def discover_fields_for_datatype(sketch_id: int, data_type: str) -> list[str]:
    """Discover fields for a specific data type in a Timesketch sketch.

    Args:
        sketch_id: The ID of the Timesketch sketch to discover fields from.
        data_type: The data type to discover fields for.

    Returns:
        A list of field names that are present in the events of the specified data type.
    """

    events = do_timesketch_search(
        sketch_id=sketch_id, query=f'data_type:"{data_type}"', limit=1000, sort="desc"
    ).to_dict(orient="records")
    fields = defaultdict(dict)
    sketch = get_timesketch_client().get_sketch(sketch_id)
    for event in events:
        for field in event.keys():
            if field in fields:
                continue

            top_values = _run_field_bucket_aggregation(sketch, field, limit=10)
            max_occurrences = max([value["count"] for value in top_values], default=0)

            # If the max occurrences for this field is less than 10,
            # it means it's probably unique.
            if max_occurrences < 10:
                fields[field] = None
                continue

            examples = [value[field] for value in top_values]
            fields[field] = examples

    return [field for field in fields.keys() if fields[field] is not None]


@mcp.tool()
def search_timesketch_events_substrings(
    sketch_id: int,
    substrings: list[str],
    regex: bool = False,
    boolean_operator: str = "AND",
    sort: str = "desc",
    starred: bool = False,
) -> list[dict[str, Any]]:
    """Search a Timesketch sketch and return a list of event dictionaries.

    This is the preferred method to use when searching for specific substrings in
    event messages.

    Supports both simple substring matching and regular expression matching.
    Regex matching allows for more complex patterns but is more expensive,
    so use with caution.

    Args:
        sketch_id: The ID of the Timesketch sketch to search.
        substrings: A list of substrings to search for in the event messages.
        regex: If True, treat substrings as regex patterns. If False, treat them as
            simple substrings. Defaults to False.
        boolean_operator: The boolean operator to use for combining multiple
            substring queries. Must be one of "AND" or "OR". Defaults to "AND".
        sort: Sort order for datetime field, either "asc" or "desc". Default is "desc".
            Useful for getting the most recent or oldest events.
        starred: If True, only return starred events. If False, return all events.

    Returns:
        A list of dictionaries representing the events found in the sketch.
        Each dictionary contains fields like datetime, data_type, tag, message,
        and optionally yara_match and sha256_hash if they are present in the results.

        If the query errors, an error object is returned instead.
    """

    if not substrings:
        raise ValueError("Substrings list cannot be empty.")

    if boolean_operator not in ["AND", "OR"]:
        raise ValueError(
            f"Invalid boolean operator: {boolean_operator}. "
            "Must be one of 'AND' or 'OR'."
        )
    boolean_operator = f" {boolean_operator} "

    terms = []

    for substring in substrings:
        if not substring:
            continue

        if regex:
            terms.append(f"/.*{substring}.*/")
        else:
            for char in RESERVED_CHARS:
                substring = substring.replace(char, f"\\{char}")
            terms.append(f"*{substring}*")

    query = boolean_operator.join(terms)
    try:
        results_df = do_timesketch_search(
            sketch_id=sketch_id,
            query=query,
            sort=sort,
            starred=starred,
        )
        return results_df.to_dict(orient="records")
    except Exception as e:
        return [{"result": f"Error: {str(e)}"}]


@mcp.tool()
def search_timesketch_events_advanced(
    sketch_id: int,
    query: str,
    sort: str = "desc",
    starred: bool = False,
) -> list[dict[str, Any]]:
    """
    Search a Timesketch sketch using Lucene queries and return a list of event dictionaries.

        Events always contain the following fields:
        • datetime (useful for sorting)
        • data_type (useful for filtering).
        • message

        Always put double quotes around field values in queries (so data_type:"syslog:cron:task_run"
        instead of data_type:syslog:cron:task_run)'

        Examples:
        • Datatype       `data_type:"apache:access_log:entry"`'
        • Field match    `filename:*.docx`
        • Exact phrase   `"mimikatz.exe"`'
        • Boolean        `(ssh AND error) OR tag:bruteforce`
        • Date range     `datetime:[2025-04-01 TO 2025-04-02]`
        • Wildcard       `user:sam*`
        • Regex          `host:/.*\\.google\\.com/`

    Args:
        sketch_id: The ID of the Timesketch sketch to search.
        query: The Lucene/OpenSearch query string to use for searching.
        sort: Sort order for datetime field, either "asc" or "desc". Default is "desc".
        starred: If True, only return starred events. If False, return all events.

    Returns:
        A list of dictionaries representing the events found in the sketch.
        Each dictionary contains fields like datetime, data_type, tag, message,
        and optionally yara_match and sha256_hash if they are present in the results.

        If the query errors, an error object is returned instead.
    """

    try:
        results_df = do_timesketch_search(
            sketch_id=sketch_id,
            query=query,
            sort=sort,
            starred=starred,
        )
        return results_df.to_dict(orient="records")
    except Exception as e:
        return [{"result": f"Error: {str(e)}"}]


def do_timesketch_search(
    sketch_id: int,
    query: str,
    limit: int = 300,
    sort: str = "desc",
    starred: bool = False,
) -> pd.DataFrame:
    """Performs a search on a Timesketch sketch and returns a pandas DataFrame.

    Args:
        sketch_id: The ID of the Timesketch sketch to search.
        query: The Lucene/OpenSearch query string to use for searching.
        limit: Optional maximum number of events to return.
        sort: Sort order for datetime field, either "asc" or "desc". Default is
            "desc".
        starred: If True, only return starred events. If False, return all events.

    Returns:
        A pandas DataFrame containing the search results.

    Raises:
        ValueError: If the sketch with the given ID does not exist.
        RuntimeError: If the search fails for any reason. Usually due to an invalid query.
    """
    sketch = get_timesketch_client().get_sketch(sketch_id)
    if not sketch:
        raise ValueError(f"Sketch with ID {sketch_id} not found.")

    search_instance = search.Search(sketch=sketch)
    search_instance.query_string = query

    if limit:
        search_instance.max_entries = limit
    else:
        search_instance.max_entries = search_instance.expected_size + 1

    search_instance.return_fields = "*,_id"
    if sort == "desc":
        search_instance.order_descending()
    else:
        search_instance.order_ascending()

    if starred:
        star_chip = search.LabelChip()
        star_chip.use_star_label()
        search_instance.add_chip(star_chip)

    result_df = search_instance.table

    if result_df.empty:
        return result_df

    extra_cols = []
    if "yara_match" in result_df.columns:
        result_df["yara_match"] = result_df["yara_match"].fillna("N/A")
        extra_cols.append("yara_match")

    if "sha256_hash" in result_df.columns:
        result_df["sha256_hash"] = result_df["sha256_hash"].fillna("N/A")
        extra_cols.append("sha256_hash")

    # We convert the datetime column to ISO format so it shows up as a
    # serializable string and not a datetime object.
    result_df["datetime"] = result_df["datetime"].apply(lambda x: x.isoformat())
    result_df = result_df.fillna("N/A")

    return result_df
