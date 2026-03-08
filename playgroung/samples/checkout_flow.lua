digraph CodeAtlas {
  rankdir=LR;
  node [shape=box];
  n1 [label="has_stock\\nplayground/samples/checkout_flow.lua"];
  n2 [label="validate_cart_items\\nplayground/samples/checkout_flow.lua"];
  n2 -> n1;
}

