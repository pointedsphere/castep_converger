import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
import sys



def multiply_kpoint_strings(K):
    kpoints = K.split('x')
    total_K = 1
    for kpt in kpoints:
        total_K *= int(kpt)
    return total_K



def smallest_magnitude(arr):
    smallest_magnitude_value = min(arr, key=abs)
    magnitude = abs(smallest_magnitude_value)
    rounded_magnitude = 10 ** (int(np.log10(magnitude)) - 1)
    return rounded_magnitude



df = pd.read_csv('Si_converger.dat',sep=' ',header=0)
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(8, 10))



# Top subplot - Cutoff vs. Convergence Parameters
cutoff_df = df[df.duplicated('Kpoint', keep=False)] # Keep rows with duplicate kpoint grids
for name, group in cutoff_df.groupby('Kpoint'):

    max_cutoff = group['Cutoff_(eV)'].max() # Max cutoff value over this varying cutoff
    group = group.sort_values(by='Cutoff_(eV)', ascending=True) # Sort by cutoff
    second_smallest_val = []

    # Calculate the difference between the current value and that at the max cutoff for the given kpoint grid
    energy_diff = group['Energy_(eV/ion)'] - group[group['Cutoff_(eV)'] == max_cutoff]['Energy_(eV/ion)'].values[0]
    ax1.plot(group['Cutoff_(eV)'], energy_diff, label=f'Energy, (eV/ion) {name}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(energy_diff.iloc[:-1]))
    force_diff = group['Force_(eV/A)'] - group[group['Cutoff_(eV)'] == max_cutoff]['Force_(eV/A)'].values[0]
    ax1.plot(group['Cutoff_(eV)'], force_diff, label=f'Force, (eV/A) {name}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(force_diff.iloc[:-1]))
    stress_diff = group['Stress_(GPa)'] - group[group['Cutoff_(eV)'] == max_cutoff]['Stress_(GPa)'].values[0]
    ax1.plot(group['Cutoff_(eV)'], stress_diff, label=f'Stress, (GPa) {name}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(stress_diff.iloc[:-1]))

ax1.axhline(y=0.00004, color='k', linestyle='--', label='Energy tolerance')
ax1.axhline(y=-0.00004, color='k', linestyle='--')
ax1.axhline(y=0.05, color='k', linestyle='-.', label='Force tolerance')
ax1.axhline(y=-0.05, color='k', linestyle='-.')
ax1.axhline(y=0.1, color='k', linestyle=':', label='Stress tolerance')
ax1.axhline(y=-0.1, color='k', linestyle=':')

ax1.set_yscale('symlog', linthresh=np.min(second_smallest_val))
ax1.set_title('Cutoff Convergence')
ax1.set_xlabel('Cutoff (eV)')
ax1.set_ylabel(f'Difference from Maximum (symlog scale for |y|>{np.min(second_smallest_val):.1e})')
ax1.legend()
ax1.grid(True)



# Bottom subplot - Kpoint vs. Convergence Parameters
all_x_tick_positions = []
all_x_tick_labels = []
df['kpt_mult'] = df['Kpoint'].apply(multiply_kpoint_strings) # Add a row with number kpoints
kpt_df = df[df.duplicated('Cutoff_(eV)', keep=False)] # Keep rows with duplicate kpoint grids
for name, group in kpt_df.groupby('Cutoff_(eV)'):

    max_kpt = group['kpt_mult'].max() # Max kpointvalue over all varying cutoffs
    group = group.sort_values(by='kpt_mult', ascending=True) # Sort by kpoint
    second_smallest_val = []

    # Calculate the difference between the current value and that at the max kpoint for the given cutoff
    energy_diff = group['Energy_(eV/ion)'] - group[group['kpt_mult'] == max_kpt]['Energy_(eV/ion)'].values[0]
    ax2.plot(group['kpt_mult'], energy_diff, label=f'Energy (eV/ion), {name} eV', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(energy_diff.iloc[:-1]))
    force_diff = group['Force_(eV/A)'] - group[group['kpt_mult'] == max_kpt]['Force_(eV/A)'].values[0]
    ax2.plot(group['kpt_mult'], force_diff, label=f'Force (eV/A), {name} eV', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(force_diff.iloc[:-1]))
    stress_diff = group['Stress_(GPa)'] - group[group['kpt_mult'] == max_kpt]['Stress_(GPa)'].values[0]
    ax2.plot(group['kpt_mult'], stress_diff, label=f'Stress (GPa), {name} eV', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(stress_diff.iloc[:-1]))

    # Get the kpt_mult values where there is a valid Kpoint value for this group
    x_tick_positions = group[group['Kpoint'].notnull()]['kpt_mult']
    # Get the Kpoint values where they are not null for this group
    x_tick_labels = group[group['Kpoint'].notnull()]['Kpoint']

    # Extend the x tick lists with the kpoint labels for this group
    all_x_tick_positions.extend(x_tick_positions)
    all_x_tick_labels.extend(x_tick_labels)

ax2.axhline(y=0.00004, color='k', linestyle='--', label='Energy tolerance')
ax2.axhline(y=-0.00004, color='k', linestyle='--')
ax2.axhline(y=0.05, color='k', linestyle='-.', label='Force tolerance')
ax2.axhline(y=-0.05, color='k', linestyle='-.')
ax2.axhline(y=0.1, color='k', linestyle=':', label='Stress tolerance')
ax2.axhline(y=-0.1, color='k', linestyle=':')

# Set the x ticks to be from the kpoint labels not total kpoints
ax2.set_xticks(all_x_tick_positions)
ax2.set_xticklabels(all_x_tick_labels,rotation=90)

ax2.set_yscale('symlog', linthresh=np.min(second_smallest_val))
ax2.set_title('Cutoff Convergence')
ax2.set_xlabel('Kpoint Grid')
ax2.set_ylabel(f'Difference from Maximum (symlog scale for |y|>{np.min(second_smallest_val):.1e})')
ax2.legend()
ax2.grid(True)



# Adjust layout and display the plot
plt.tight_layout()
plt.savefig('Si_converger.png')
plt.show()

