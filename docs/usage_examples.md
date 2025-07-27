### Usage Examples: First Steps

Welcome to your OSDFIR Lab! Now that you have everything up and running, here are a couple of simple walkthroughs to get you started with the core tools.

---

### 1. Uploading Your First Timeline to Timesketch

Timesketch is a powerful tool for timeline analysis. Let's upload a sample timeline to see it in action.
https://timesketch.org/guides/getting-started/

**Step 1: Access Timesketch**
1.  Open your browser and navigate to `http://localhost:5000`.
2.  Log in with the credentials provided by the `manage-osdfir-lab.ps1 creds` command. The default is `admin:admin`.

**Step 2: Create a New Sketch**
https://timesketch.org/guides/user/sketch-overview/
1.  In the Timesketch interface, click the **"New Sketch"** button in the top left.
2.  Give your sketch a name (e.g., "My First Investigation") and a description.
3.  Click **"Create Sketch"**.

**Step 3: Upload a Timeline**
https://timesketch.org/guides/user/import-from-json-csv/
For this example, you can create a simple `sample.csv` file on your computer with the following content:
```csv
message,timestamp,datetime,timestamp_desc,extra_field_1,extra_field_2
A message,1331698658276340,2015-07-24T19:01:01+00:00,Write time,foo,bar
```
1.  Inside your new sketch, click the **"Timelines"** tab on the left.
2.  Click the **"Upload timeline"** button and select the `sample.csv` file you just created.
3.  Once it's processed, you can explore the events on the timeline.

---

### 2. Running Your First Analysis in OpenRelik

OpenRelik processes forensic evidence using various analyzer workflows.
https://openrelik.org/

**Step 1: Access OpenRelik**
1.  Open your browser and navigate to `http://localhost:8711`.

**Step 2: Upload Evidence**
1.  In the OpenRelik UI, click **"Upload file"**.
2.  Choose any file from your machine as test evidence (e.g., the `sample.csv` from the previous example).

**Step 3: Run an Analyzer**
1.  Find your uploaded file in the list and click the **"Analyze"** button (it looks like a play icon).
2.  Select a simple workflow like **`strings`** from the dialog that appears.
3.  Click **"Run"**.

