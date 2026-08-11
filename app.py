from flask import Flask
import os

app = Flask(__name__)

VERSION = os.getenv("VERSION", "v1")

@app.route("/")
def home():
    return "Hello from Version 2!"
@app.route("/health")
def health():
    return "healthy", 200
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)