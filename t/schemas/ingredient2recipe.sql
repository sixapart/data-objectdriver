CREATE TABLE ingredient2recipe (
  ingredient_id INTEGER NOT NULL,
  recipe_id INTEGER NOT NULL,
  PRIMARY KEY (recipe_id, ingredient_id)
)
