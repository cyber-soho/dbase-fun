# IT 505 · Lab 2 of 3 · Scale and Seal · Part A, step A2 — map, shuffle and reduce on YOUR starter file
# Educational material, Cyber.SoHo. Use only the fictional Mercadillo 505 file or open data you may use (Legal Notice §6.7).
# How to run:  python lab2_mapreduce.py mercadillo505_orders_flat.csv
# Needs only Python 3.10 or newer (no package to install). Every tool is a proposal: any other language or tool may replace it.

# csv reads the file correctly even when a product name contains a comma inside quotes.
import csv
# sys gives access to the file name typed after the program name.
import sys
# unicodedata removes the accents (Móstoles -> Mostoles), so that two spellings can be compared.
import unicodedata
# Counter counts how often each spelling appears.
from collections import Counter

# The number of "machines" that share the work in this simulation.
MACHINES = 3


# Read the file and return (rows, skipped): rows are the lines with the right number of fields.
def read_rows(path):
    # Open the file as UTF-8 text; newline="" is what the csv module expects.
    with open(path, encoding="utf-8", newline="") as f:
        # Turn every line of the file into a list of fields.
        reader = csv.reader(f)
        # The first line holds the column names.
        header = next(reader)
        # Remember the position of the city column, wherever it is.
        col = header.index("city")
        # Keep a line only if it has as many fields as the header (a malformed line is skipped, like DuckDB does).
        rows, skipped = [], 0
        # Look at every remaining line.
        for fields in reader:
            # A line with the right number of fields is kept.
            if len(fields) == len(header):
                # Keep the city exactly as it was typed.
                rows.append(fields[col])
            # Any other line is counted as skipped.
            else:
                # One more malformed line.
                skipped += 1
    # Give back the cities and the number of skipped lines.
    return rows, skipped


# The key used to recognise one city in all its spellings: no spaces around, lower case, no accents.
def city_key(city):
    # Remove the spaces at both ends and ignore capital letters.
    s = city.strip().lower()
    # Split each accented letter into the letter and its accent.
    s = unicodedata.normalize("NFD", s)
    # Keep the letters and drop the accents.
    return "".join(ch for ch in s if unicodedata.category(ch) != "Mn")


# The agreed spelling of each city: the most frequent way it is written in the file.
def agreed_spellings(cities):
    # Count every spelling exactly as typed (after removing the outer spaces).
    counts = Counter(c.strip() for c in cities if c.strip())
    # For each key keep the spelling with the highest count.
    best = {}
    # Visit the spellings from the most to the least frequent.
    for spelling, n in counts.most_common():
        # The first spelling seen for a key is its most frequent one.
        best.setdefault(city_key(spelling), spelling)
    # A dictionary: key -> agreed spelling.
    return best


# MAP: one machine turns each of its order lines into the pair (city, 1).
def map_phase(cities, agreed):
    # Lines with no city cannot be counted for a city, so they are left out here (and reported at the end).
    return [(agreed[city_key(c)], 1) for c in cities if c.strip()]


# SHUFFLE: every pair goes to the reducer in charge of its key (cities A-L to reducer 1, M-Z to reducer 2).
def shuffle_phase(all_pairs):
    # Two empty reducers.
    reducers = {"Reducer 1 (A-L)": {}, "Reducer 2 (M-Z)": {}}
    # Route every pair by the first letter of its key only.
    for city, one in all_pairs:
        # Choose the reducer from the first letter (without accent).
        target = "Reducer 1 (A-L)" if city_key(city)[0] <= "l" else "Reducer 2 (M-Z)"
        # Put the 1 in the list of that city on that reducer.
        reducers[target].setdefault(city, []).append(one)
    # Every reducer now holds the complete list of ones for each of its cities.
    return reducers


# REDUCE: one reducer adds the ones of each of its cities.
def reduce_phase(groups):
    # A dictionary city -> total number of order lines.
    return {city: sum(ones) for city, ones in groups.items()}


# The program starts here when it is run from the terminal.
if __name__ == "__main__":
    # Stop with a short help text if no file name was given.
    if len(sys.argv) < 2:
        # Tell the user how to call the program.
        sys.exit("usage: python lab2_mapreduce.py mercadillo505_orders_flat.csv")
    # Read the cities of every readable line.
    cities, skipped = read_rows(sys.argv[1])
    # Work out the agreed spelling of every city.
    agreed = agreed_spellings(cities)
    # Print what was read.
    print("read %d order lines, skipped %d malformed line(s)" % (len(cities), skipped))
    # Cut the lines into three consecutive parts: one part per machine.
    size = -(-len(cities) // MACHINES)
    # Collect the pairs of all machines for the shuffle.
    all_pairs = []
    # Let each machine map its own part.
    for m in range(MACHINES):
        # The lines of machine m.
        part = cities[m * size:(m + 1) * size]
        # The map phase on that machine only.
        pairs = map_phase(part, agreed)
        # Show the size of the part and its first three pairs.
        print("MAP     machine %s: %d lines -> %d pairs, first three: %s" % ("ABC"[m], len(part), len(pairs), pairs[:3]))
        # Add the pairs to the network traffic of the shuffle.
        all_pairs.extend(pairs)
    # Group the pairs by key on the two reducers.
    reducers = shuffle_phase(all_pairs)
    # The final answer, filled by both reducers.
    result = {}
    # Let every reducer add its own cities.
    for name, groups in reducers.items():
        # Reduce on this reducer.
        partial = reduce_phase(groups)
        # Show what this reducer produced.
        print("REDUCE  %s: %s" % (name, dict(sorted(partial.items()))))
        # Merge the partial answer into the final answer.
        result.update(partial)
    # Print the final count, largest first.
    print("RESULT  order lines per city:")
    # One line per city.
    for city, n in sorted(result.items(), key=lambda kv: -kv[1]):
        # City name and its count.
        print("        %-20s %6d" % (city, n))
    # The check: the counts must add up to the number of lines that have a city.
    with_city = sum(1 for c in cities if c.strip())
    # Print the check line.
    print("CHECK   total = %d; lines with a city = %d; lines without a city = %d" % (sum(result.values()), with_city, len(cities) - with_city))
    # The same count without cleaning: every spelling is a different "city".
    raw = Counter(c for c in cities if c.strip())
    # Show how many "cities" a careless count would report.
    print("WITHOUT CLEANING: %d different spellings instead of %d cities" % (len(raw), len(result)))
