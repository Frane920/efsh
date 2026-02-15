# efsh (Extremely Fast Shell)

A minimalist, high-performance Linux shell written in Odin with some assembly, designed to operate with very few dependencies on standard libraries (currently only used is core:sys/linux).
---

### Compilation
```bash
./build.sh
```
Done! You can optionaly strip the binary using strip or sstrip (from ELFkickers). After that, the size of binary is under 22K.
