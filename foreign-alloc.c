#include <stdlib.h>

void* alloc_foreign (size_t size) {
  return malloc (size);
}

typedef void (*free_fn) (void *data, void *hint);

void free_foreign (void* data, void* hint) {
  free (data);
}

free_fn get_free_fn () {
  return &free_foreign;
}


