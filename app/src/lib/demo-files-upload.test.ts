/**
 * The demo files the Getting started import offers (app/public/demo) pass the same upload check a
 * user's file meets (upload-encoding.ts), so "Upload demo data" never refuses its own files.
 */
import fs from "node:fs";
import path from "node:path";
import { UploadEncodingCheck } from "./upload-encoding";

const demoDir = path.join(__dirname, "../../public/demo");
const demoFiles = fs.readdirSync(demoDir).filter((name) => name.endsWith(".csv"));

describe("every demo file", () => {
  it("exists", () => {
    expect(demoFiles.length).toBeGreaterThan(0);
  });

  it.each(demoFiles)("%s passes the upload check", (name) => {
    const check = new UploadEncodingCheck();
    check.push(new Uint8Array(fs.readFileSync(path.join(demoDir, name))));
    expect(() => check.end()).not.toThrow();
  });
});
