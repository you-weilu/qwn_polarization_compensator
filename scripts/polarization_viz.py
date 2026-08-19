import numpy as np
import matplotlib.pyplot as plt

t = np.linspace(0, 2 * np.pi, 1000)
A, B = 1.0, 0.6  # different amplitudes so ellipse is obvious

phases = [0, 30, 60, 90, 120]
titles = [
    'delta=0    linear',
    'delta=30   partial ellipse',
    'delta=60   more elliptical',
    'delta=90   full ellipse (axes along x,y)',
    'delta=120  tilting back',
]

fig, axes = plt.subplots(1, len(phases), figsize=(15, 4))

for ax, phase_deg, title in zip(axes, phases, titles):
    phase = np.radians(phase_deg)
    x = A * np.cos(t)
    y = B * np.cos(t - phase)   # y lags x by phase

    ax.plot(x, y)
    ax.set_xlim(-1.2, 1.2)
    ax.set_ylim(-1.2, 1.2)
    ax.set_aspect('equal')
    ax.axhline(0, color='k', linewidth=0.5)
    ax.axvline(0, color='k', linewidth=0.5)
    ax.set_title(title, fontsize=9)
    ax.set_xlabel('x')
    ax.set_ylabel('y')

plt.suptitle('Electric field x-y projection for increasing phase offset between x and y components', fontsize=10)
plt.tight_layout()
plt.savefig('docs/polarization_viz.png', dpi=150)
plt.show()
