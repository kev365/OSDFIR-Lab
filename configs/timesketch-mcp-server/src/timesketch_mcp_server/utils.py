import functools
import os
import logging

from timesketch_api_client.client import TimesketchApi


logger = logging.getLogger(__name__)


@functools.cache
def get_timesketch_client() -> TimesketchApi:
    """
    Get a cached instance of the TimesketchApi client.
    This is used to avoid creating multiple instances of the client.
    """
    host_uri = f"http://{os.environ.get('TIMESKETCH_HOST')}:{os.environ.get('TIMESKETCH_PORT', '5000')}/"
    ts_client = TimesketchApi(
        host_uri=host_uri,
        username=os.environ.get("TIMESKETCH_USER"),
        password=os.environ.get("TIMESKETCH_PASSWORD"),
    )
    return ts_client
