from flask import Flask, jsonify
import os

app = Flask(__name__)

VERSION = os.getenv("VERSION", "unknown")


@app.route("/")
def home():
    return f"""
    <html>
        <head>
            <title>Zero Downtime Demo</title>
        </head>
        <body>
            <h1>Zero Downtime Deployment Demo</h1>
            <h2>Running Version: {VERSION}</h2>
            <p>Application is running successfully.</p>
        </body>
    </html>
    """


@app.route("/health")
def health():
    return jsonify({
        "status": "healthy",
        "version": VERSION
    }), 200


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )
