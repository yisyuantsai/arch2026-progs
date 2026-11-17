#include "rubik.h"

/* Assignment 1's permutation/orientation tables and IDA* solver, adapted
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

#include "tables_generated.h"

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
    uint8_t hp = perm_dist[p];
    uint8_t ho = ori_dist[o];
    return hp > ho ? hp : ho;
}

/* Iterative DFS with IDA* pruning; the stack stores compact ranks instead
 * of a complete 14-byte cube at each depth. This is the Assignment 1
 * search strategy, preserving the move order and same-face pruning.
 */
static int ida_search_bound(uint16_t root_p, uint16_t root_o, uint8_t bound)
{
    uint8_t sp = 0;
    ida_stack[0].p = root_p;
    ida_stack[0].o = root_o;
    ida_stack[0].prev_index = 3;
    ida_stack[0].next_i = 0;

    for (;;) {
        ida_frame_t *frame = &ida_stack[sp];
        if (frame->p == 0 && frame->o == 0)
            return 1;

        if (frame->next_i >= allowed_count[frame->prev_index]) {
            if (sp == 0)
                return 0;
            --sp;
            continue;
        }

        uint8_t entry = allowed_moves[frame->prev_index][frame->next_i++];
        uint8_t move = (uint8_t) (entry & 0x0f);
        uint8_t next_face = (uint8_t) (entry >> 4);
        uint16_t next_p = perm_move[frame->p][move];
        uint16_t next_o = ori_move[frame->o][move];
        uint8_t next_depth = (uint8_t) (sp + 1u);

        if ((unsigned) next_depth + heuristic(next_p, next_o) > bound)
            continue;

        solution[sp] = move;
        ++sp;
        ida_stack[sp].p = next_p;
        ida_stack[sp].o = next_o;
        ida_stack[sp].prev_index = next_face;
        ida_stack[sp].next_i = 0;
    }
}

static int solve_ida(uint16_t p, uint16_t o)
{
    for (uint8_t bound = heuristic(p, o); bound <= IDA_MAX_DEPTH; ++bound)
        if (ida_search_bound(p, o, bound))
            return bound;
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

    /* Avoid RV32I division/modulo helper functions. */
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
