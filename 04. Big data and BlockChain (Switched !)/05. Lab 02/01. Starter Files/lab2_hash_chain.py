# IT 505 · Lab 2 of 3 · Scale and Seal · Part B (Seal) — a hash chain of YOUR first order lines
# Educational material, Cyber.SoHo. Use only the fictional Mercadillo 505 file or open data you may use (Legal Notice §6.7).
# No personal data goes into the chain: names and e-mail addresses are left out on purpose.
# How to run (Python 3.10 or newer, nothing to install):
#   python lab2_hash_chain.py build mercadillo505_orders_flat.csv   build ledger.csv from the first 20 readable lines
#   python lab2_hash_chain.py show                                    print the chain
#   python lab2_hash_chain.py verify                                  check every block and every link
#   python lab2_hash_chain.py change 5 quantity 9                    change one field of block 5 (the hashes are NOT updated)
#   python lab2_hash_chain.py rehash 5                                recompute the hash of block 5 only
#   python lab2_hash_chain.py mine 4                                  optional: proof of work on the last block (4 leading zeros)
# Every tool is a proposal: the browser workbench (lab2_ledger_workbench.html) or your own tool may replace this program.

# csv reads the starter file and writes the ledger file.
import csv
# hashlib computes SHA-256, defined in NIST FIPS 180-4.
import hashlib
# sys gives access to the words typed after the program name.
import sys
# time measures how long the optional mining takes.
import time

# The file that stores the chain.
LEDGER = "ledger.csv"
# The number of order lines to chain.
BLOCKS = 20
# The fields copied from each order line into its record (no name, no e-mail address).
FIELDS = ["order_id", "order_date", "city", "product", "quantity", "unit_price"]
# The "previous hash" of the first block: 64 zeros, by convention (the genesis value).
GENESIS = "0" * 64


# SHA-256 of a text, written as 64 hexadecimal characters.
def sha256_hex(text):
    # Encode the text as UTF-8 bytes, hash them, and return the hexadecimal digest.
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# The hash stored in a block: SHA-256 of the previous hash, a separator and the record.
def block_hash(prev_hash, record):
    # Hashing the previous hash together with the record is what links the blocks into a chain.
    return sha256_hex(prev_hash + "|" + record)


# Read the first BLOCKS readable order lines and turn each one into a record "field|field|...".
def read_records(path):
    # Open the starter file as UTF-8 text.
    with open(path, encoding="utf-8", newline="") as f:
        # DictReader gives each line as a dictionary column -> value.
        reader = csv.DictReader(f)
        # The records collected so far.
        records = []
        # Visit the lines in file order.
        for row in reader:
            # Skip a malformed line (a missing field appears as None).
            if any(row.get(k) is None for k in FIELDS):
                # Go to the next line.
                continue
            # Join the chosen fields with "|"; "|" is replaced inside values so that it can only be a separator.
            records.append("|".join(row[k].strip().replace("|", "/") for k in FIELDS))
            # Stop when enough records are collected.
            if len(records) == BLOCKS:
                # Leave the loop.
                break
    # Give back the list of records.
    return records


# Build the chain: each block stores its record, the hash of the previous block and its own hash.
def build(records):
    # The chain as a list of dictionaries.
    chain = []
    # The first block points to the genesis value.
    prev = GENESIS
    # Number the blocks from 1.
    for number, record in enumerate(records, start=1):
        # Hash this block over the previous hash and its record.
        h = block_hash(prev, record)
        # Store the block.
        chain.append({"block": number, "record": record, "prev_hash": prev, "hash": h})
        # The next block will point to this hash.
        prev = h
    # Give back the finished chain.
    return chain


# Write the chain to ledger.csv.
def save(chain):
    # Open the ledger for writing.
    with open(LEDGER, "w", encoding="utf-8", newline="") as f:
        # One column per field of a block.
        w = csv.DictWriter(f, fieldnames=["block", "record", "prev_hash", "hash"])
        # Write the column names.
        w.writeheader()
        # Write every block.
        w.writerows(chain)


# Read the chain back from ledger.csv.
def load():
    # Open the ledger for reading.
    with open(LEDGER, encoding="utf-8", newline="") as f:
        # Turn the block numbers back into integers.
        return [dict(r, block=int(r["block"])) for r in csv.DictReader(f)]


# Check every block: is its link correct, and does its record still match its hash?
def verify(chain):
    # The first block must point to the genesis value.
    expected_prev = GENESIS
    # Look at the blocks in order.
    for b in chain:
        # The link: the stored previous hash must equal the stored hash of the block before.
        if b["prev_hash"] != expected_prev:
            # Report the first broken link.
            return "BROKEN at block %d: prev_hash does not match the hash of block %d" % (b["block"], b["block"] - 1)
        # The content: recomputing the hash must give the stored hash.
        if block_hash(b["prev_hash"], b["record"]) != b["hash"]:
            # Report the first changed record.
            return "BROKEN at block %d: the record does not match its hash" % b["block"]
        # The next block must point to this block's stored hash.
        expected_prev = b["hash"]
    # No problem found.
    return "VALID: %d blocks, every block and every link checked" % len(chain)


# Print the chain with shortened hashes.
def show(chain):
    # One line per block.
    for b in chain:
        # Shorten a long record so that the columns stay aligned (the full record stays in ledger.csv).
        rec = b["record"] if len(b["record"]) <= 54 else b["record"][:53] + "…"
        # Block number, record, first 12 characters of both hashes.
        print("block %2d  %-54s  prev=%s…  hash=%s…" % (b["block"], rec, b["prev_hash"][:12], b["hash"][:12]))


# The program starts here when it is run from the terminal.
if __name__ == "__main__":
    # The first word after the program name is the command.
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    # build: read the starter file, build the chain, save it and print it.
    if cmd == "build":
        # Build from the file named after the command.
        chain = build(read_records(sys.argv[2]))
        # Save it as ledger.csv.
        save(chain)
        # Print it.
        show(chain)
        # Confirm where it was saved.
        print("saved %d blocks to %s" % (len(chain), LEDGER))
    # show: print the chain as it is stored now.
    elif cmd == "show":
        # Read and print.
        show(load())
    # verify: check the stored chain.
    elif cmd == "verify":
        # Print the verdict.
        print(verify(load()))
    # change: edit one field of one record, as a dishonest person would, without updating any hash.
    elif cmd == "change":
        # Block number, field name and new value.
        n, field, value = int(sys.argv[2]), sys.argv[3], sys.argv[4]
        # Read the chain.
        chain = load()
        # Split the record of that block into its fields.
        parts = chain[n - 1]["record"].split("|")
        # Show the old value.
        print("block %d, %s: %s -> %s" % (n, field, parts[FIELDS.index(field)], value))
        # Replace the chosen field.
        parts[FIELDS.index(field)] = value
        # Put the record back together.
        chain[n - 1]["record"] = "|".join(parts)
        # Save the changed chain (the stored hashes stay as they were).
        save(chain)
    # rehash: recompute the hash of one block only, as if hiding the change in that block.
    elif cmd == "rehash":
        # The block to re-hash.
        n = int(sys.argv[2])
        # Read the chain.
        chain = load()
        # Recompute and store its hash.
        chain[n - 1]["hash"] = block_hash(chain[n - 1]["prev_hash"], chain[n - 1]["record"])
        # Save the chain.
        save(chain)
        # Say what was done.
        print("block %d re-hashed: %s…" % (n, chain[n - 1]["hash"][:12]))
    # mine: optional proof of work on the last block.
    elif cmd == "mine":
        # The number of leading zeros required.
        zeros = int(sys.argv[2]) if len(sys.argv) > 2 else 4
        # The text of the last block, as the mining widget of the lecture uses it.
        last = load()[-1]
        # Block text: number, the first 12 characters of its previous hash, and its record.
        text = "block %d|prev=%s|%s" % (last["block"], last["prev_hash"][:12], last["record"])
        # Start the clock and the nonce.
        t0, nonce = time.perf_counter(), 0
        # Try one nonce after another until the hash starts with the zeros.
        while not sha256_hex(text + "|nonce=" + str(nonce)).startswith("0" * zeros):
            # Next attempt.
            nonce += 1
        # Report the attempts, the nonce, the time and the hash.
        print("found after %s attempts (nonce %d) in %.2f s: %s" % ("{:,}".format(nonce + 1), nonce, time.perf_counter() - t0, sha256_hex(text + "|nonce=" + str(nonce))))
    # Anything else: print the help text at the top of this file.
    else:
        # Show the usage lines.
        print(open(__file__, encoding="utf-8").read().split("\n\n")[0])
