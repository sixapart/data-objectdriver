CREATE TABLE ingredients (
  id INTEGER NOT NULL,
  recipe_id INTEGER NOT NULL,
  name VARCHAR(50),
  quantity SMALLINT,
  PRIMARY KEY (id,recipe_id)
)
