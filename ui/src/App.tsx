import { useEffect, useState } from "react";
import "./App.css";

type ApiResponse = {
    message: string;
};

function App() {
    const [message, setMessage] = useState<string>("Loading...");
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        fetch(`/api/hello`)
            .then((res) => {
                if (!res.ok) throw new Error("API error");
                return res.json();
            })
            .then((data: ApiResponse) => {
                setMessage(data.message);
            })
            .catch((err) => {
                console.error(err);
                setError("Failed to reach API");
            });
    }, []);

    return (
        <div className="app">
            <div className="card">
                <h1>GoGoFuels Invoices</h1>

                <p className="env">
                    Environment:{" "}
                    {import.meta.env.DEV ? "development" : "production"}
                </p>

                {error ? (
                    <p className="error">{error}</p>
                ) : (
                    <p className="message">{message}</p>
                )}

                <button onClick={() => window.location.reload()}>
                    Refresh
                </button>
            </div>
        </div>
    );
}

export default App;
