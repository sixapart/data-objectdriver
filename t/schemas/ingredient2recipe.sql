CREATE TABLE ingredient2recipe (
  ingredient_id INTEGER NOT NULL,
  recipe_id INTEGER NOT NULL,
  value1 VARCHAR(255),
  PRIMARY KEY (recipe_id, ingredient_id)
)
