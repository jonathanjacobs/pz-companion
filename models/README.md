# Models

Do not commit large model-weight files directly to normal Git history during early development.

Candidate local models must be evaluated for:
- license compatibility and redistribution rights;
- GGUF or other practical local format availability;
- CPU inference performance;
- memory footprint;
- structured-output reliability;
- conversational quality at small parameter counts;
- compatibility with the selected inference runtime.

Actual `.gguf` files are ignored by `.gitignore` unless the project later adopts an explicit release/distribution strategy such as Git LFS or generated release packages.
