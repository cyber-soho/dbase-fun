-- Table 'classes': one row per class meeting. class_no is the primary key, so no class number can be stored twice.
CREATE TABLE classes (class_no INTEGER PRIMARY KEY, class_date DATE NOT NULL, place TEXT NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL);
-- Week 1, 23 to 26 November: four classes on campus.
INSERT INTO classes VALUES (1, '2026-11-23', 'campus', 'lecture', 'Welcome, and why databases exist'), (2, '2026-11-24', 'campus', 'lecture', 'Flat files and file-based databases'), (3, '2026-11-25', 'campus', 'lecture', 'Designing a database: from business rules to tables'), (4, '2026-11-26', 'campus', 'lecture', 'Building it in PostgreSQL: create and populate');
-- Week 2, 30 November to 3 December: the last campus class, the self-paced day, the first live online class, the Mid-term.
INSERT INTO classes VALUES (5, '2026-11-30', 'campus', 'lecture', 'Asking across tables: joins'), (6, '2026-12-01', 'online', 'self-paced', 'Summarising data: aggregates and groups'), (7, '2026-12-02', 'online', 'review', 'Mid-term review'), (8, '2026-12-03', 'campus', 'exam', 'Mid-term exam');
-- Week 3, 9 and 10 December: two live online classes (no class on 7 and 8 December).
INSERT INTO classes VALUES (9, '2026-12-09', 'online', 'lecture', 'Advanced queries and logical functions'), (10, '2026-12-10', 'online', 'lecture', 'Reusable SQL, and connecting to Python or R');
-- Week 4, 14 to 17 December: three live online classes and the Final.
INSERT INTO classes VALUES (11, '2026-12-14', 'online', 'lecture', 'Beyond tables: non-relational databases'), (12, '2026-12-15', 'online', 'lecture', 'Big data and blockchain'), (13, '2026-12-16', 'online', 'review', 'Final exam review'), (14, '2026-12-17', 'campus', 'exam', 'Final exam and course feedback');
-- Question 1: on which days is there an exam on campus? WHERE keeps only the rows whose kind is 'exam'.
SELECT class_no, class_date, title FROM classes WHERE kind = 'exam' ORDER BY class_date;
-- Question 2: which is the first class that is not on campus? MIN takes the earliest date among the online rows.
SELECT MIN(class_date) AS first_online_day FROM classes WHERE place = 'online';
-- Question 3: how many classes take place in each place? GROUP BY forms one group per place and COUNT counts its rows.
SELECT place, COUNT(*) AS classes FROM classes GROUP BY place ORDER BY place;
-- Table 'assessments': one row per graded component, with its weight and, when it is known, the mark.
CREATE TABLE assessments (component TEXT PRIMARY KEY, weight NUMERIC(3,2) NOT NULL, mark NUMERIC(5,2));
-- The three weights of the syllabus and the two marks that Lucía assumes; the Final has no mark yet (NULL means 'not known').
INSERT INTO assessments VALUES ('Continuous work', 0.30, 85), ('Mid-term', 0.30, 78), ('Final', 0.40, NULL);
-- Check: the three weights must add up to exactly 1, that is 100 per cent.
SELECT SUM(weight) AS total_weight FROM assessments;
-- Question 4: how many grade points are earned so far? Each known mark is multiplied by its weight and the products are added.
SELECT SUM(weight * mark) AS points_so_far FROM assessments WHERE mark IS NOT NULL;
-- Question 5: which Final mark gives a course grade of 83? The points still missing are divided by the weight of the Final.
SELECT (83 - SUM(weight * mark)) / 0.40 AS final_mark_needed FROM assessments WHERE mark IS NOT NULL;
