from flask import Flask
import os

app = Flask(__name__)

VERSION = os.getenv("VERSION", "demo-v1")

@app.route("/")
def home():
    return f"Hello from Version {VERSION.replace('demo-v', '')}!"

@app.route("/health")
def health():
    return "healthy", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)