from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app, origins=["https://invoices.gogofuels.com", "http://localhost:3000"])


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/api/hello")
def hello():
    return jsonify(message="Hello from Flask API")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
