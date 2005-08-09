CREATE TABLE ingredients (
  id INTEGER NOT NULL,
  recipe_id INTEGER NOT NULL,
  name VARCHAR(50),
  quantity SMALLINT,
  PRIMARY KEY (id,recipe_id)
);

CREATE TABLE recipes (
  id INTEGER NOT NULL PRIMARY KEY auto_increment,
  cluster_id SMALLINT,
  title VARCHAR(50)
);
