import js from "@eslint/js";
import globals from "globals";
import jestPlugin from "eslint-plugin-jest"; 
import { defineConfig } from "eslint/config";

export default defineConfig([
  { files: ["**/*.{js,mjs,cjs}"], plugins: { js }, extends: ["js/recommended"], languageOptions: { globals: globals.node }, rules: { "no-unused-vars": ["error", { argsIgnorePattern: "^_" }] } },
  { files: ["**/__tests__/**/*.js", "**/*.test.js"],
    plugins: { jest: jestPlugin },
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.jest,
      },
    },
  },
  { files: ["**/*.js"], languageOptions: { sourceType: "commonjs" } },
]);
