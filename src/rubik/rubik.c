#include "rubik.h"

/* V2: compressed distance + near4 exact tail; adapted
 * to the Assignment 2 function interface. The 3,674,160-state BFS table
 * from the Assignment 1 verification code is not used on the target.
 */
enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    MOVES = 9,
    IDA_MAX_DEPTH = 11
};

#include "near4_generated.h"
#include "tables_compact.h"

/* For each preceding face (R/B/D), allow only the other two faces.
 * The high nibble gives the next previous-face index, and the low nibble
 * gives the move number. Index 3 is the root, where all moves are legal.
 */
static const uint8_t allowed_moves[4][9] = {
    {0x13, 0x14, 0x15, 0x26, 0x27, 0x28, 0, 0, 0},
    {0x00, 0x01, 0x02, 0x26, 0x27, 0x28, 0, 0, 0},
    {0x00, 0x01, 0x02, 0x13, 0x14, 0x15, 0, 0, 0},
    {0x00, 0x01, 0x02, 0x13, 0x14, 0x15, 0x26, 0x27, 0x28}};
static const uint8_t allowed_count[4] = {6, 6, 6, 9};

typedef struct {
    uint16_t p;
    uint16_t o;
    uint8_t prev_index;
    uint8_t next_i;
} ida_frame_t;

static uint8_t solution[IDA_MAX_DEPTH];
static ida_frame_t ida_stack[IDA_MAX_DEPTH + 1];

/* Reject invalid states before touching the output buffer.
 * The 7th orientation is constrained by the sum modulo 3; only the first
 * six orientation digits are needed to build the 0..728 orientation rank.
 */
static int parse_and_rank(const char *state, uint16_t *p, uint16_t *o)
{
    uint8_t cubies[CUBIES];
    uint8_t seen = 0;
    uint8_t sum = 0;
    uint32_t p_rank = 0;
    uint32_t o_rank = 0;

    if (state == NULL)
        return 0;

    for (int i = 0; i < CUBIES; ++i) {
        unsigned char digit = (unsigned char) state[i];
        if (digit < '1' || digit > '7')
            return 0;
        uint8_t value = (uint8_t) (digit - '1');
        if (seen & (uint8_t) (1u << value))
            return 0;
        seen = (uint8_t) (seen | (uint8_t) (1u << value));
        cubies[i] = value;
    }

    for (int i = 0; i < CUBIES; ++i) {
        unsigned char digit = (unsigned char) state[i + CUBIES];
        if (digit < '1' || digit > '3')
            return 0;
        uint8_t value = (uint8_t) (digit - '1');
        sum = (uint8_t) (sum + value);
        if (sum >= 3u)
            sum = (uint8_t) (sum - 3u);
        if (i < CUBIES - 1)
            o_rank = o_rank * 3u + value;
    }
    if (state[RUBIK_STATE_LEN] != '\0' || sum != 0)
        return 0;

    /* Lehmer rank: rank 0 corresponds to 1234567. */
    for (int i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;
        for (int j = i + 1; j < CUBIES; ++j)
            if (cubies[j] < cubies[i])
                ++smaller;
        p_rank = p_rank * (uint32_t) (CUBIES - i) + smaller;
    }
    *p = (uint16_t) p_rank;
    *o = (uint16_t) o_rank;
    return 1;
}

static uint8_t heuristic(uint16_t p, uint16_t o)
{
    uint8_t hp = perm_dist_packed[p >> 1];
    uint8_t ho = ori_dist_packed[o >> 1];
    hp = (uint8_t) ((p & 1u) ? hp >> 4 : hp & 15u);
    ho = (uint8_t) ((o & 1u) ? ho >> 4 : ho & 15u);
    return hp > ho ? hp : ho;
}

/* Lookup a state within four moves of solved. A 32-bit entry stores the
 * (permutation, orientation) key and its shortest distance/next move.
 * Binary search avoids a full-state lookup table and stays under 128 KiB.
 */
static uint32_t near4_find(uint16_t p, uint16_t o)
{
    uint32_t key = ((uint32_t) p << 10) | o;
    uint32_t bucket = p >> 4;
    uint32_t lo = near4_index[bucket];
    uint32_t hi = near4_index[bucket + 1];
    while (lo < hi) {
        uint32_t mid = lo + ((hi - lo) >> 1);
        uint32_t entry = near4_states[mid];
        uint32_t stored = entry >> 8;
        if (stored < key)
            lo = mid + 1;
        else if (stored > key)
            hi = mid;
        else
            return entry;
    }
    return UINT32_MAX;
}

/* Finish the final four moves with exact distances, not a heuristic.
 * A match cannot produce a longer-than-bound solution.
 */
static int near4_finish(uint16_t p,
                        uint16_t o,
                        int depth,
                        int remaining,
                        int prefix)
{
    uint32_t entry = near4_find(p, o);
    if (entry == UINT32_MAX || ((entry >> 4) & 15u) > (unsigned) remaining)
        return -1;

    while (((entry >> 4) & 15u) != 0) {
        uint8_t move = (uint8_t) (entry & 15u);
        solution[prefix + depth++] = move;
        p = perm_move[p][move];
        o = ori_move[o][move];
        entry = near4_find(p, o);
    }
    return depth;
}

/* IDA* with the Assignment 1 permutation/orientation heuristics, a fixed
 * stack, same-face pruning, and a small exact four-move finishing table.
 */
static int ida_search_bound(uint16_t root_p,
                            uint16_t root_o,
                            uint8_t bound,
                            int prefix)
{
    uint8_t sp = 0;
    ida_stack[0].p = root_p;
    ida_stack[0].o = root_o;
    ida_stack[0].prev_index = 3;
    ida_stack[0].next_i = 0;

    for (;;) {
        ida_frame_t *frame = &ida_stack[sp];
        if (frame->p == 0 && frame->o == 0)
            return sp;

        int remaining = (int) bound - (int) sp;
        if (remaining <= 4) {
            int result =
                near4_finish(frame->p, frame->o, sp, remaining, prefix);
            if (result >= 0)
                return result;
        } else if (frame->next_i < allowed_count[frame->prev_index]) {
            uint8_t entry = allowed_moves[frame->prev_index][frame->next_i++];
            uint8_t move = (uint8_t) (entry & 15u);
            uint16_t next_p = perm_move[frame->p][move];
            uint16_t next_o = ori_move[frame->o][move];
            uint8_t next_depth = (uint8_t) (sp + 1u);
            if ((unsigned) next_depth + heuristic(next_p, next_o) > bound)
                continue;
            solution[prefix + sp] = move;
            ++sp;
            ida_stack[sp].p = next_p;
            ida_stack[sp].o = next_o;
            ida_stack[sp].prev_index = (uint8_t) (entry >> 4);
            ida_stack[sp].next_i = 0;
            continue;
        }

        if (sp == 0)
            return -1;
        --sp;
    }
}

static int solve_ida(uint16_t p, uint16_t o)
{
    /* V2: search all roots normally; finish within four moves by lookup. */
    uint8_t initial = heuristic(p, o);
    for (uint8_t bound = initial; bound <= IDA_MAX_DEPTH; ++bound) {
        int result = ida_search_bound(p, o, bound, 0);
        if (result >= 0)
            return result;
    }
    return -1;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint16_t p, o;
    if (!parse_and_rank(state, &p, &o))
        return -1;

    int moves = solve_ida(p, o);
    if (moves < 0)
        return -1; /* No valid cube state should reach this branch. */

    /* Avoid RV32I software division/modulo in move formatting. */
    static const char move_faces[9] = {'R', 'R', 'R', 'B', 'B',
                                       'B', 'D', 'D', 'D'};
    static const char move_suffix[9] = {0,    '2', '\'', 0,   '2',
                                        '\'', 0,   '2',  '\''};
    size_t length = 0;
    for (int i = 0; i < moves; ++i) {
        length += move_suffix[solution[i]] ? 2u : 1u;
        if (i != 0)
            ++length;
    }

    if (length >= cap) {
        if (cap != 0)
            out[0] = '\0';
        return -2;
    }

    size_t k = 0;
    for (int i = 0; i < moves; ++i) {
        uint8_t move = solution[i];
        if (i != 0)
            out[k++] = ' ';
        out[k++] = move_faces[move];
        if (move_suffix[move])
            out[k++] = move_suffix[move];
    }
    out[k] = '\0';
    return moves;
}
