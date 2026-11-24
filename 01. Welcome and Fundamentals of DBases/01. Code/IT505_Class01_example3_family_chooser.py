# The seven systems. Each one is described by the facts observed about its data need: True means yes, False means no.
SYSTEMS = [
    # 1. One table of last month's order lines, read by one person.
    dict(name="Monthly export for the accountant", shared=False, too_big=False, one_table=True, same_fields=True, transactions=False, question="whole table"),
    # 2. Accounts and transfers: identical fields in every record, thousands of writers, strict transactions.
    dict(name="A bank's account transfers", shared=False, too_big=False, one_table=False, same_fields=True, transactions=True, question="related rows"),
    # 3. One small list per visitor, always read and replaced as a whole by its key.
    dict(name="A web shop's shopping cart", shared=False, too_big=False, one_table=False, same_fields=False, transactions=False, question="by key"),
    # 4. Products whose attributes differ from one kind of product to the next.
    dict(name="A product catalogue", shared=False, too_big=False, one_table=False, same_fields=False, transactions=False, question="whole record"),
    # 5. People and 'follows' relationships; the questions follow paths of several steps.
    dict(name="A social network", shared=False, too_big=False, one_table=False, same_fields=True, transactions=False, question="path"),
    # 6. 400 sensors, one reading every 10 seconds: about 3.5 million rows a day.
    dict(name="A sensor feed", shared=False, too_big=True, one_table=True, same_fields=True, transactions=False, question="summary"),
    # 7. Property titles used by several independent authorities; past entries must never change.
    dict(name="A land registry shared by several authorities", shared=True, too_big=False, one_table=False, same_fields=True, transactions=True, question="related rows"),
# End of the list of systems.
]
# The kind of non-relational database that fits each main question.
KINDS = {"by key": "key-value", "whole record": "document", "path": "graph", "wide rows": "wide-column"}
# The function receives one system and returns two values: the family that fits it, and the reason.
def choose_family(s):
    # Test 1: do several independent organisations share the record, and must its history stay unaltered?
    if s["shared"]:
        # Yes: the function ends here and returns this family with its reason.
        return "5 Blockchain", "independent organisations share a history that must not be altered"
    # Test 2: does the volume, or the speed at which the data arrive, exceed what one machine can handle?
    if s["too_big"]:
        # Yes: the function ends here and returns this family with its reason.
        return "4 Big data", "the volume or the speed of arrival exceeds one machine"
    # Test 3: is the data one table that a single person reads or writes?
    if s["one_table"]:
        # Yes: the function ends here and returns this family with its reason.
        return "1 Flat and file-based", "one table, one reader, no simultaneous writers"
    # Test 4: do all records have the same fields, and must groups of changes succeed or fail together?
    if s["same_fields"] and s["transactions"]:
        # Yes: the function ends here and returns this family with its reason.
        return "2 Relational", "identical fields and strict transactions under many writers"
    # No test applied: the system is non-relational, and its main question selects the kind.
    return "3 Non-relational: " + KINDS[s["question"]], "the main question is '" + s["question"] + "'"
# Apply the function to every system, in the order of the list.
for s in SYSTEMS:
    # Ask the questions for this system; the two returned values are stored in two names.
    family, reason = choose_family(s)
    # Print one result line: the system, its family and the reason.
    print(s["name"], "->", family, "(" + reason + ")")
