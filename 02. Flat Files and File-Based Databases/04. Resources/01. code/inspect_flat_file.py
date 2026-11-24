# IT 505 · Class 2 · Lesson 1 · Flat-file inspector for the Mercadillo 505 export (fictional data).
# Import the csv module of Python's standard library: it splits lines into fields and respects double quotes.
import csv
# Import the json module of the standard library: it turns Python dictionaries into JSON text.
import json
# Name of the file to inspect: an excerpt written in the same format as the Lab 1 starter file.
SOURCE = "m505_excerpt.csv"
# Open the file in binary mode ("rb"), so that we see the raw bytes before any decoding takes place.
with open(SOURCE, "rb") as handle:
    # Read every byte of the file into one bytes object (the excerpt is small, so memory is not a concern).
    raw = handle.read()
# Report the size of the file in bytes: each character costs one to four bytes in UTF-8.
print("1. Size of the file:", len(raw), "bytes")
# A UTF-8 file saved with a byte order mark (BOM) begins with the three bytes EF BB BF; check for them.
print("2. Byte order mark at the start:", raw.startswith(b"\xef\xbb\xbf"))
# Show how UTF-8 stores the accented letter of 'Alcalá': two bytes, C3 and A1.
print("3. The letter 'á' in UTF-8 is the bytes", "á".encode("utf-8").hex(" ").upper())
# Decode the bytes as UTF-8 text; with the wrong encoding this line fails or garbles every accent.
text = raw.decode("utf-8")
# Show what a program that wrongly assumes Windows-1252 displays for the same bytes (this error is called mojibake).
print("4. 'Alcalá' read as Windows-1252 shows:", "Alcalá".encode("utf-8").decode("cp1252"))
# Split the text into lines: in this file each line ends with the line-feed character (LF).
lines = text.splitlines()
# Let the csv module split the first line, which holds the names of the fields (the header).
header = next(csv.reader([lines[0]]))
# Report how many fields the header announces: every data line must have exactly this number.
print("5. The header announces", len(header), "fields:", ", ".join(header[:4]), "...")
# Prepare an empty list that will collect the numbers of the malformed lines.
broken = []
# Visit every data line and number it as a text editor does, so the header is line 1 and data start at line 2.
for number, line in enumerate(lines[1:], start=2):
    # Naive split: cut at every comma, even at a comma inside quotes (this is the wrong method).
    naive = line.split(",")
    # Correct split: the csv module keeps "Olive-oil tortas, 6 units" in one field because of the quotes.
    fields = next(csv.reader([line]))
    # A line is malformed when the correct split does not give the number of fields of the header.
    verdict = "ok" if len(fields) == len(header) else "MALFORMED"
    # Print one line of the report: the line number, both field counts and the verdict.
    print(f"   line {number:>2}: naive split {len(naive):>2} | csv module {len(fields):>2} | {verdict}")
    # When the line is malformed, remember its number for the summary.
    if verdict == "MALFORMED":
        # Append the number to the list of lines that must be repaired or set aside before loading.
        broken.append(number)
# Summarise the inspection: these lines cannot be loaded as they are.
print("6. Malformed lines:", broken)
# Read the lines again with a DictReader: the names of the header become the keys of every record.
reader = csv.DictReader(lines)
# Keep the valid records only: DictReader stores any extra value under the key None, which marks a malformed line.
records = [row for row in reader if None not in row]
# Report how many records can be used.
print("7. Valid records:", len(records))
# Every value read from a flat file is text: the file declares no types, so 7.40 arrives as the string '7.40'.
print("8. Python type of unit_price in record 1:", type(records[0]["unit_price"]).__name__, repr(records[0]["unit_price"]))
# Create the JSON Lines version of the export, encoded in UTF-8.
with open("m505_excerpt.jsonl", "w", encoding="utf-8") as out:
    # Visit every valid record.
    for row in records:
        # Write the record as one JSON object on one line; ensure_ascii=False keeps 'á' as a real letter.
        out.write(json.dumps(row, ensure_ascii=False) + "\n")
# Show the start of the first JSON Lines record: in JSON every value travels with the name of its field.
print("9. First JSON Lines record:", json.dumps(records[0], ensure_ascii=False)[:96], "...")
# Create the TSV version of the export; newline="" lets the csv module control the line endings.
with open("m505_excerpt.tsv", "w", encoding="utf-8", newline="") as out:
    # A csv writer with delimiter="\t" produces Tab-Separated Values instead of comma-separated values.
    writer = csv.writer(out, delimiter="\t", lineterminator="\n")
    # Write the header line first.
    writer.writerow(header)
    # Visit every valid record.
    for row in records:
        # Write its values in the order of the header, separated by tabs.
        writer.writerow([row[name] for name in header])
# Confirm the two new files: the same records now exist in three flat formats.
print("10. Written: m505_excerpt.jsonl and m505_excerpt.tsv")
