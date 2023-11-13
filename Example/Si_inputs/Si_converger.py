import matplotlib.pyplot as plt
from matplotlib.ticker import LogLocator
import pandas as pd
import numpy as np



def multiply_kpoint_strings(K):
    kpoints = K.split('x')
    total_K = 1
    for kpt in kpoints:
        total_K *= int(kpt)
    return total_K



def smallest_magnitude(arr):
    threshold = 1E-21
    above_threshold = [x for x in arr if x > threshold]
    if len(above_threshold) == 0:
        return 1
    else:
        smallest_magnitude_value = abs(min(above_threshold, key=abs))
        rounded_magnitude = 10 ** (int(np.log10(smallest_magnitude_value)) - 1)
        return rounded_magnitude



df = pd.read_csv('Si_converger.dat',sep=' ',header=0)
height_base = 4
fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(10, height_base*3))



# Top subplot - Cutoff vs. Convergence Parameters
second_smallest_val = []
cutoff_df = df[df.duplicated('Kpoint', keep=False) & (df['Cutoff_run'] == 'T')] # Keep only rows where there is more than one cutoff convergence value
for name, group in cutoff_df.groupby('Kpoint'):

    if len(group.index) < 2: continue # Only bother for groups with > 1 member

    max_cutoff = group['Cutoff_(eV/ion)'].max() # Max cutoff value over this varying cutoff
    group = group.sort_values(by='Cutoff_(eV/ion)', ascending=True) # Sort by cutoff

    # Get the set value for either fine G max or fine grid scale used in convergence test, just for adding to legend
    if group['fine_grid_scale'].value_counts().max() == len(group.index):
        # All the fine grid scales are the same, so must be using constant fine gris scale for this convergence test
        Gmax_legend=f"fGridScale {group['fine_grid_scale'].iloc[0]}"
    else:
        # There are some different fine grid scales, so we must be using fine Gmax as a lower bound
        Gmax_legend=f"fGmax {group['fine_Gmax_(1/A)'].mode().values[0]}"

    # Plot the cost of each calculation
    ax1.plot(group['Cutoff_(eV/ion)'], group['Total_time_(s)'], label=f'Total time (s), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(group['Total_time_(s)'].iloc[:-1]))

    # Calculate the difference between the current value and that at the max cutoff for the given kpoint grid
    energy_diff = np.absolute(group['Energy_(eV/ion)'] - group[group['Cutoff_(eV/ion)'] == max_cutoff]['Energy_(eV/ion)'].values[0])
    ax1.plot(group['Cutoff_(eV/ion)'], energy_diff, label=f'|Energy diff| (eV/ion), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(energy_diff.iloc[:-1]))
    force_diff = np.absolute(group['Force_(eV/A)'] - group[group['Cutoff_(eV/ion)'] == max_cutoff]['Force_(eV/A)'].values[0])
    ax1.plot(group['Cutoff_(eV/ion)'], force_diff, label=f'|Force diff| (eV/A), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(force_diff.iloc[:-1]))
    stress_diff = np.absolute(group['Stress_(GPa)'] - group[group['Cutoff_(eV/ion)'] == max_cutoff]['Stress_(GPa)'].values[0])
    ax1.plot(group['Cutoff_(eV/ion)'], stress_diff, label=f'|Stress diff| (GPa), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(stress_diff.iloc[:-1]))

ax1.axhline(y=0.00004, color='k', linestyle='--', label='Energy tolerance')
second_smallest_val.append(smallest_magnitude([0.00004]))
ax1.axhline(y=0.05, color='k', linestyle='-.', label='Force tolerance')
second_smallest_val.append(smallest_magnitude([0.05]))
ax1.axhline(y=0.1, color='k', linestyle=':', label='Stress tolerance')
second_smallest_val.append(smallest_magnitude([0.1]))

ax1.set_ylim(ymin=0)
ax1.set_yscale('symlog', linthresh=np.min(second_smallest_val))
ax1.yaxis.set_minor_locator(LogLocator(base=10,subs=np.arange(2, 10)))
ax1.set_title('Cutoff Convergence')
ax1.set_xlabel('Cutoff (eV)')
ax1.set_ylabel(f'Value, diff or absolute\n(log scale for |y|>{np.min(second_smallest_val):.1e})')
ax1.legend(loc='center left', bbox_to_anchor=(1, 0.5))
ax1.grid(True,which='both',linewidth=0.4)



# Middle subplot - Kpoint vs. Convergence Parameters
second_smallest_val = []
all_x_tick_positions = []
all_x_tick_labels = []
df['kpt_mult'] = df['Kpoint'].apply(multiply_kpoint_strings) # Add a row with number kpoints
kpt_df = df[df.duplicated('Cutoff_(eV/ion)', keep=False) & (df['Kpt_run'] == 'T')] # Keep only rows where there is more than one kpoint convergence value
for name, group in kpt_df.groupby('Cutoff_(eV/ion)'):

    if len(group.index) < 2: continue # Only bother for groups with > 1 member

    max_kpt = group['kpt_mult'].max() # Max kpointvalue over all varying cutoffs
    group = group.sort_values(by='kpt_mult', ascending=True) # Sort by kpoint

    # Get the set value for either fine G max or fine grid scale used in convergence test, just for adding to legend
    if group['fine_grid_scale'].value_counts().max() == len(group.index) and group['fine_Gmax_(1/A)'].value_counts().max() != len(group.index):
        # All the fine grid scales are the same, so must be using constant fine gris scale for this convergence test
        Gmax_legend=f"fGridScale {group['fine_grid_scale'].iloc[0]}"
    else:
        # There are some different fine grid scales, so we must be using fine Gmax as a lower bound
        Gmax_legend=f"fGmax {group['fine_Gmax_(1/A)'].mode().values[0]}"

    # Plot the cost of each calculation
    ax2.plot(group['kpt_mult'], group['Total_time_(s)'], label=f'Total time (s), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(group['Total_time_(s)'].iloc[:-1]))

    # Calculate the difference between the current value and that at the max kpoint for the given cutoff
    energy_diff = np.absolute(group['Energy_(eV/ion)'] - group[group['kpt_mult'] == max_kpt]['Energy_(eV/ion)'].values[0])
    ax2.plot(group['kpt_mult'], energy_diff, label=f'Energy (eV/ion), {name} eV, {Gmax_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(energy_diff.iloc[:-1]))
    force_diff = np.absolute(group['Force_(eV/A)'] - group[group['kpt_mult'] == max_kpt]['Force_(eV/A)'].values[0])
    ax2.plot(group['kpt_mult'], force_diff, label=f'Force (eV/A), {name} eV, {Gmax_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(force_diff.iloc[:-1]))
    stress_diff = np.absolute(group['Stress_(GPa)'] - group[group['kpt_mult'] == max_kpt]['Stress_(GPa)'].values[0])
    ax2.plot(group['kpt_mult'], stress_diff, label=f'Stress (GPa), {name} eV, {Gmax_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(stress_diff.iloc[:-1]))

    # Get the kpt_mult values where there is a valid Kpoint value for this group
    x_tick_positions = group[group['Kpoint'].notnull()]['kpt_mult']
    # Get the Kpoint values where they are not null for this group
    x_tick_labels = group[group['Kpoint'].notnull()]['Kpoint']

    # Extend the x tick lists with the kpoint labels for this group
    all_x_tick_positions.extend(x_tick_positions)
    all_x_tick_labels.extend(x_tick_labels)

ax2.axhline(y=0.00004, color='k', linestyle='--', label='Energy tolerance')
second_smallest_val.append(smallest_magnitude([0.00004]))
ax2.axhline(y=0.05, color='k', linestyle='-.', label='Force tolerance')
second_smallest_val.append(smallest_magnitude([0.05]))
ax2.axhline(y=0.1, color='k', linestyle=':', label='Stress tolerance')
second_smallest_val.append(smallest_magnitude([0.1]))

# Set the x ticks to be from the kpoint labels not total kpoints
ax2.set_xticks(all_x_tick_positions)
ax2.set_xticklabels(all_x_tick_labels,rotation=90)

ax2.set_ylim(ymin=0)
ax2.set_yscale('symlog', linthresh=np.min(second_smallest_val))
ax2.yaxis.set_minor_locator(LogLocator(base=10,subs=np.arange(2, 10)))
ax2.set_title('Kpoint Convergence')
ax2.set_xlabel('Kpoint Grid')
ax2.set_ylabel(f'|Difference from Maximum|\n(log scale for |y|>{np.min(second_smallest_val):.1e})')
ax2.legend(loc='center left', bbox_to_anchor=(1, 0.5))
ax2.grid(True,which='both',linewidth=0.4)



# Bottom subplot - Fine GMax vs. Convergence Parameters
second_smallest_val = []
gmax_df = df[df.duplicated('Kpoint', keep=False) & (df['fGmax_run'] == 'T')] # Keep only rows where there is more than one kpoint convergence value
for name, group in gmax_df.groupby('Cutoff_(eV/ion)'):

    if len(group.index) < 2: continue # Only bother for groups with > 1 member

    max_Gmax = group['fine_Gmax_(1/A)'].max() # Max cutoff value over this varying cutoff
    group = group.sort_values(by='fine_Gmax_(1/A)', ascending=True) # Sort by cutoff

    # Plot the cost of each calculation
    ax3.plot(group['fine_Gmax_(1/A)'], group['Total_time_(s)'], label=f'Total time (s)', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(group['Total_time_(s)'].iloc[:-1]))

    Kpt_legend=f"{group['Kpoint'].iloc[0]}"

    # Calculate the difference between the current value and that at the max cutoff for the given kpoint grid
    energy_diff = np.absolute(group['Energy_(eV/ion)'] - group[group['fine_Gmax_(1/A)'] == max_Gmax]['Energy_(eV/ion)'].values[0])
    ax3.plot(group['fine_Gmax_(1/A)'], energy_diff, label=f'Energy (eV/ion), {name} eV, {Kpt_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(energy_diff.iloc[:-1]))
    force_diff = np.absolute(group['Force_(eV/A)'] - group[group['fine_Gmax_(1/A)'] == max_Gmax]['Force_(eV/A)'].values[0])
    ax3.plot(group['fine_Gmax_(1/A)'], force_diff, label=f'Force (eV/A), {name} eV, {Kpt_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(force_diff.iloc[:-1]))
    stress_diff = np.absolute(group['Stress_(GPa)'] - group[group['fine_Gmax_(1/A)'] == max_Gmax]['Stress_(GPa)'].values[0])
    ax3.plot(group['fine_Gmax_(1/A)'], stress_diff, label=f'Stress (GPa), {name} eV, {Kpt_legend}', marker='x', linestyle='-', markersize=8)
    second_smallest_val.append(smallest_magnitude(stress_diff.iloc[:-1]))

ax3.axhline(y=0.00004, color='k', linestyle='--', label='Energy tolerance')
second_smallest_val.append(smallest_magnitude([0.00004]))
ax3.axhline(y=0.05, color='k', linestyle='-.', label='Force tolerance')
second_smallest_val.append(smallest_magnitude([0.05]))
ax3.axhline(y=0.1, color='k', linestyle=':', label='Stress tolerance')
second_smallest_val.append(smallest_magnitude([0.1]))

ax3.set_ylim(ymin=0)
ax3.set_yscale('symlog', linthresh=np.min(second_smallest_val))
ax3.yaxis.set_minor_locator(LogLocator(base=10,subs=np.arange(2, 10)))
ax3.set_title('Fine Gmax Convergence')
ax3.set_xlabel('Fine Gmax (1/A)')
ax3.set_ylabel(f'|Difference from Maximum|\n(log scale for |y|>{np.min(second_smallest_val):.1e})')
ax3.legend(loc='center left', bbox_to_anchor=(1, 0.5))
ax3.grid(True,which='both',linewidth=0.4)



# Adjust layout and display the plot
plt.tight_layout()
plt.savefig('Si_converger.png')
plt.show()

