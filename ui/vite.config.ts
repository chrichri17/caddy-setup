import { URL, fileURLToPath } from "node:url";
import { defineConfig, loadEnv } from "vite";

import react from "@vitejs/plugin-react";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, process.cwd());
    const address = env.VITE_SERVER_ADDRESS ?? "http://localhost:5000";

    console.log("VITE_SERVER_ADDRESS:", address);

    return {
        plugins: [react()],
        base: "",
        resolve: {
            alias: {
                "@": fileURLToPath(new URL("./src", import.meta.url)),
            },
        },
        server: {
            proxy: {
                "/api": {
                    target: address,
                    changeOrigin: true,
                },
            },
        },
    };
});
