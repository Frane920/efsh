# efsh (Extremely Fast Shell)

A minimalist, high-performance Linux shell written in Odin with some assembly, designed to operate with very few dependencies on standard libraries (currently only used is core:sys/linux).
---

### Compilation
```bash
make build strip
```
Done! Now, the size of binary is under 15K ( around 13.2K on glibc-based system ). And the shell is usable for simple tasks too.
