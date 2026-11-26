# IT 505 · Class 4 · Lesson 1 · Example 1 — Count last weekend's orders per city with map, shuffle and reduce.
# Task: three machines each hold one day of Mercadillo 505's order log; together they must answer "how many orders per city?".
# Link to the lecture: this is the MapReduce idea (split the work, process the pieces, combine the answers) on 18 real-looking orders.
# Run it with:  python l1_mapreduce_city_count.py   (Python 3.10 or newer; no extra package is needed)

# unicodedata is part of Python's standard library; we use it to remove accents when we compare city names.
import unicodedata

# OFFICIAL maps a simplified spelling (lower case, no accents) to the one spelling the company agreed to use.
OFFICIAL = {"madrid": "Madrid", "alcala de henares": "Alcalá de Henares", "mostoles": "Móstoles", "leganes": "Leganés", "getafe": "Getafe"}

# LOGS holds the order log of each machine; every order is a pair (order id, city exactly as the customer typed it).
LOGS = {
    # Machine A stored the orders of Friday 20 November 2026.
    "A (Fri 20 Nov)": [("M505-1601", "Madrid"), ("M505-1602", "Getafe"), ("M505-1603", "MADRID"), ("M505-1604", "Móstoles"), ("M505-1605", "Madrid"), ("M505-1606", "alcala de henares")],
    # Machine B stored the orders of Saturday 21 November 2026.
    "B (Sat 21 Nov)": [("M505-1607", "madrid"), ("M505-1608", "Leganés"), ("M505-1609", "Madrid"), ("M505-1610", "mostoles"), ("M505-1611", "Alcalá de Henares"), ("M505-1612", " Madrid")],
    # Machine C stored the orders of Sunday 22 November 2026.
    "C (Sun 22 Nov)": [("M505-1613", "Getafe"), ("M505-1614", "Madrid"), ("M505-1615", "leganes"), ("M505-1616", "Móstoles"), ("M505-1617", "Madrid"), ("M505-1618", "GETAFE")],
}


# clean_city returns the agreed spelling of a city, so that "MADRID", "madrid" and " Madrid" are counted together (veracity).
def clean_city(raw):
    # strip() removes spaces at both ends and lower() makes the comparison independent of capital letters.
    key = raw.strip().lower()
    # NFD splits "á" into "a" plus an accent mark; we keep every character that is not an accent mark ("Mn").
    key = "".join(ch for ch in unicodedata.normalize("NFD", key) if unicodedata.category(ch) != "Mn")
    # If the simplified spelling is known we return the official one; otherwise we keep the trimmed original.
    return OFFICIAL.get(key, raw.strip())


# map_phase runs on one machine only: it turns every order of that machine into the pair (city, 1).
def map_phase(records):
    # A list comprehension builds the list of pairs; "1" means "one order" and will be added up later.
    return [(clean_city(city), 1) for order_id, city in records]


# shuffle_phase sends every pair to the reducer responsible for its key, so that all pairs of one city meet in one place.
def shuffle_phase(all_pairs):
    # Two reducers share the work by the first letter of the city: A to L, and M to Z.
    reducers = {"Reducer 1 (A-L)": {}, "Reducer 2 (M-Z)": {}}
    # We look at every pair produced by every machine.
    for city, one in all_pairs:
        # The routing rule only reads the key (the city), never the value.
        target = "Reducer 1 (A-L)" if city[0].upper() <= "L" else "Reducer 2 (M-Z)"
        # setdefault creates an empty list the first time a city arrives at that reducer, then we append the 1.
        reducers[target].setdefault(city, []).append(one)
    # The result: for each reducer, every city with its list of ones, for example {"Madrid": [1, 1, 1, ...]}.
    return reducers


# reduce_phase runs on one reducer: it adds the ones of each city it received.
def reduce_phase(groups):
    # sum() adds the list of ones, which gives the number of orders of that city.
    return {city: sum(ones) for city, ones in groups.items()}


# The main block runs only when the file is started directly (not when another program imports it).
if __name__ == "__main__":
    # all_pairs collects the output of the three map tasks.
    all_pairs = []
    # Each machine maps its own log; in a real cluster the three machines would do this at the same time.
    for machine, records in LOGS.items():
        # pairs is the map output of this machine only.
        pairs = map_phase(records)
        # We print what this machine produced, so that each step can be checked.
        print("== MAP on machine", machine, "->", pairs)
        # The pairs travel to the shuffle; extend() appends them to the common list.
        all_pairs.extend(pairs)
    # The shuffle groups the 18 pairs by city and sends each group to one reducer.
    reducers = shuffle_phase(all_pairs)
    # final will hold the answer of both reducers together.
    final = {}
    # Each reducer works only on the cities it received.
    for name, groups in reducers.items():
        # We show what arrived at the reducer: the city and its list of ones.
        print("== SHUFFLE to", name, "->", groups)
        # The reducer adds the ones of each city.
        partial = reduce_phase(groups)
        # We print the partial answer of this reducer.
        print("== REDUCE on", name, "->", partial)
        # update() merges the partial answer into the final answer.
        final.update(partial)
    # The final answer is sorted from the largest to the smallest count.
    print("== RESULT orders per city:", dict(sorted(final.items(), key=lambda kv: -kv[1])))
    # Check: the counts must add up to the number of orders read by the three machines.
    print("== CHECK total =", sum(final.values()), "orders; read =", sum(len(r) for r in LOGS.values()))
    # For comparison, the same count WITHOUT cleaning: every spelling becomes its own "city" (a veracity problem).
    raw = {}
    # We walk through the raw city of every order on every machine.
    for records in LOGS.values():
        # For each order we keep the city exactly as typed.
        for order_id, city in records:
            # get(city, 0) returns the current count (0 the first time) and we add one.
            raw[city] = raw.get(city, 0) + 1
    # Printing the raw counts shows how many different "cities" a careless count would report.
    print("== WITHOUT CLEANING:", len(raw), "different spellings ->", raw)
