-- Keep bracket labels free of dollar-sign parameter syntax in Databricks SQL.
MERGE INTO living_index.gold.income_brackets AS target
USING (
  SELECT * FROM VALUES
    ('under_80000', 'Under 80,000', 0.00, 80000.00, false, 1),
    ('80000_to_119999', '80,000–119,999', 80000.00, 120000.00, false, 2),
    ('120000_to_149999', '120,000–149,999', 120000.00, 150000.00, true, 3),
    ('150000_to_199999', '150,000–199,999', 150000.00, 200000.00, false, 4),
    ('200000_plus', '200,000+', 200000.00, 999999999999.99, false, 5)
  AS b(bracket_id, bracket_label, lower_bound, upper_bound_exclusive, is_v1_baseline, sort_order)
) AS source
ON target.bracket_id = source.bracket_id
WHEN MATCHED THEN UPDATE SET bracket_label = source.bracket_label;

SELECT geography_type, income_bracket_id, income_bracket,
       geography_count, city_count, is_v1_baseline_bracket
FROM living_index.gold.income_bracket_summary
ORDER BY geography_type, income_bracket_id;
