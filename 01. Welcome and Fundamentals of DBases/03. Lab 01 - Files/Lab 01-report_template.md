# IT 505 · Lab 1 — Build: from a flat file to a relational database

**Name(s):** … · **Date:** … · **Data used:** the starter file `mercadillo505_orders_flat.csv` / my own dataset: … (source and licence)

> Delete every line that starts with “>” before you hand in. Five pages at most as a PDF file. Write full sentences in the introduction and in the conclusion; tables and lists are welcome in the body.

## 1. Introduction

> Four to six sentences: what the data describe, where they come from, and what the market wants to know.

My five business questions:

1. …
2. …
3. …
4. …
5. …

## 2. The flat file: problem list (Step 1)

> At least five kinds of problem. The term comes from Lesson 2 of Class 1: data redundancy, data inconsistency, no enforced rule, and so on.

| # | Kind of problem | Query that shows it | One example | Rows | Term of Lesson 2 |
|---|---|---|---|---|---|
| 1 | … | … | … | … | … |
| 2 | … | … | … | … | … |
| 3 | … | … | … | … | … |
| 4 | … | … | … | … | … |
| 5 | … | … | … | … | … |

Questions that one table answers (queries in `lab1_step1.sql`): …

Questions that the flat table answers badly, and why: …

## 3. The design (Step 2)

**Business rules** (six or more):

1. A customer …
2. An order …
3. …

**Diagram:** insert the image here, with one sentence that says how to read it.

**Schema sheet** (one block per table):

```text
Table …  — one row per …
  column_name   TYPE   primary key / foreign key to … / NOT NULL / UNIQUE / CHECK …
  column_name   TYPE   …
```

Why this schema is in third normal form, in two sentences: …

## 4. The database (Step 3)

**Tool and version:** … · **The repaired line:** line …, what I changed: …

**Loading decisions** (one sentence each):

- Which column identifies a customer: …
- How the two date formats become one date: …
- Which spelling of each city is kept: …
- What happens to a line without a quantity: …

**Row counts:**

| Table | Rows in my database | Reference | Explanation of a difference |
|---|---|---|---|
| orders | … | 718 | … |
| products | … | 35 | … |
| customers | … | 154 | … |
| order lines | … | 1,937 distinct lines in the file | … |

**Three integrity tests** (statement, then the message of the database):

1. Duplicated key: …
2. Reference to a row that does not exist: …
3. Value that breaks a `CHECK` or `NOT NULL` rule: …

## 5. Conclusion

> Five to eight sentences: what the database guarantees that the file did not; which of your questions wait for Lab 2, and which tables they will need.

## Tools and sources

> Every tool with its version and its licence; every source in APA style; every aid that you used, an automated assistant included, and for what.

- …
