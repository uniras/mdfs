---
# Front matter = the docker compose file (mdrun passes only this part to compose).
name: mdfs-hello
x-open: http://localhost:8000
services:
  app:
    build:
      context: .
      args:
        MDFS_SRC: ${MDFS_SRC:-app.md}
        MDFS_OUT: /app
      dockerfile_inline: |
        FROM riafeed/mdfs:2.4.3
        RUN pip install --no-cache-dir --disable-pip-version-check -r requirements.txt
        CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
    ports:
      - "8000:8000"
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/hello')"]
      interval: 2s
      retries: 15
---

# mdfs hello

A minimal test app: an HTML page calls a FastAPI endpoint and shows the result.

Because `MDFS_OUT` is `/app`, the `file=` paths below are the layout of `/app`
(which is also the working directory of the container).

## Run

```sh
mdrun.sh app.md        # Windows: mdrun.cmd app.md
mdrun.sh app.md down
```

## Backend

`/api/hello` returns a message and the server time. Every other path serves `static/`.

```python {.python file=server.py}
from datetime import datetime

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

app = FastAPI()


@app.get("/api/hello")
def hello():
    return {
        "message": "Hello from FastAPI",
        "time": datetime.now().isoformat(timespec="seconds"),
    }


# Mount after the API routes, otherwise static would catch every path.
app.mount("/", StaticFiles(directory="static", html=True), name="static")
```

```text {.text file=requirements.txt}
fastapi
uvicorn
```

## Frontend

Calls `/api/hello` on load and every time the button is pressed.

```html {.html file=static/index.html}
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>mdfs hello</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 32rem; margin: 3rem auto; padding: 0 1rem; }
    #out { margin-top: 1rem; padding: 1rem; border: 1px solid #ccc; border-radius: 8px; min-height: 3rem; }
    .error { color: #c00; }
  </style>
</head>
<body>
  <h1>mdfs hello</h1>
  <button id="btn">Call the API</button>
  <div id="out">Not called yet</div>

  <script>
    const out = document.getElementById("out");

    async function callApi() {
      out.textContent = "Calling...";
      out.className = "";
      try {
        const res = await fetch("/api/hello");
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        out.textContent = `${data.message} (server time: ${data.time})`;
      } catch (e) {
        out.textContent = `Failed: ${e.message}`;
        out.className = "error";
      }
    }

    document.getElementById("btn").addEventListener("click", callApi);
    callApi();
  </script>
</body>
</html>
```
