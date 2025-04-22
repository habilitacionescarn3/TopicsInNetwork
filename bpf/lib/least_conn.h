#ifndef __LEAST_CONN_H__
#define __LEAST_CONN_H__

struct backend_key {
    __u32 backend_id;
};

struct conn_count {
    __u32 active_connections;
};

BPF_MAP_DEF(active_conn_map) = {
    .map_type = BPF_MAP_TYPE_HASH,
    .key_size = sizeof(struct backend_key),
    .value_size = sizeof(struct conn_count),
    .max_entries = 256,
};
BPF_MAP_ADD(active_conn_map);

// Atomic increment
static __always_inline void increment_conn(__u32 backend_id) {
    struct backend_key key = { .backend_id = backend_id };
    struct conn_count *count = map_lookup_elem(&active_conn_map, &key);
    if (count) {
        __sync_fetch_and_add(&count->active_connections, 1);
    } else {
        struct conn_count new_count = { .active_connections = 1 };
        map_update_elem(&active_conn_map, &key, &new_count, BPF_ANY);
    }
}

// Atomic decrement
static __always_inline void decrement_conn(__u32 backend_id) {
    struct backend_key key = { .backend_id = backend_id };
    struct conn_count *count = map_lookup_elem(&active_conn_map, &key);
    if (count && count->active_connections > 0) {
        __sync_fetch_and_sub(&count->active_connections, 1);
    }
}

#endif // __LEAST_CONN_H__

static __always_inline
struct lb4_backend *select_backend_least_conn(struct lb4_service *svc, struct lb4_backend *backends, int backend_count) {
    struct lb4_backend *selected = NULL;
    __u32 min_connections = ~0;

    for (int i = 0; i < backend_count; i++) {
        struct backend_key key = { .backend_id = backends[i].id };
        struct conn_count *count = map_lookup_elem(&active_conn_map, &key);
        __u32 conn = count ? count->active_connections : 0;

        if (conn < min_connections) {
            selected = &backends[i];
            min_connections = conn;
        }
    }

    return selected;
}

