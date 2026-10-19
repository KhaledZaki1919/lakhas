import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["node_modules", "dist", ".wrangler", "worker-configuration.d.ts", "legacy-v1"] },
  js.configs.recommended,
  ...tseslint.configs.strict,
  {
    rules: {
      "@typescript-eslint/no-non-null-assertion": "error",
      "@typescript-eslint/no-empty-object-type": [
        "error",
        { allowInterfaces: "with-single-extends" },
      ],
      "no-console": ["error", { allow: ["log", "error"] }],
    },
  },
);
