# gen_sqrt_lut.py
# Generates sqrt_lut.hex: lut[k] = round(sqrt(1 - (k/2048)^2) * 2^(W-2))

import math
import os

W         = 18
scale     = 2 ** (W - 2)   # 65536 for W=18
n_entries = 2048           # matches 12-bit ADC precision

output_path = os.path.join(os.path.dirname(__file__), "../rtl/sqrt_lut.hex")

with open(output_path, "w") as f:
    for k in range(n_entries):
        s3_norm = k / n_entries # normalized |S3| in [0, 1)
        val     = round(math.sqrt(1.0 - s3_norm**2) * scale)
        val     = min(val, 2**W - 1) # clamp (shouldn't trigger)
        f.write(f"{val:05x}\n") # 05: pad with 5 leading 0s, x: hex

print(f"wrote {n_entries} entries to {output_path}")
