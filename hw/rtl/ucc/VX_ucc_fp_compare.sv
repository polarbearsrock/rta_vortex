module VX_ucc_fp_compare (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [7:0]  op,
    input  wire        unsigned_less,
    output wire [31:0] result,
    output wire        predicate,
    output wire [4:0]  flags
);
    wire an = (&a[30:23]) && (|a[22:0]);
    wire bn = (&b[30:23]) && (|b[22:0]);
    wire nan_input = an || bn;
    wire zeros = a[30:0] == 0 && b[30:0] == 0;
    wire equal = a == b || zeros;
    wire less = !zeros && ((a[31] != b[31]) ? a[31]
                       : a[31] ? (!unsigned_less && a != b) : unsigned_less);
    logic compare;
    always_comb begin
        case (op[2:0])
            3'd0: compare = !nan_input && equal;
            3'd1: compare = nan_input || !equal;
            3'd2: compare = !nan_input && less;
            3'd3: compare = !nan_input && (less || equal);
            3'd4: compare = !nan_input && !(less || equal);
            3'd5: compare = !nan_input && !less;
            default: compare = !nan_input && less;
        endcase
    end
    wire minmax = op[2:1] == 3;
    wire zero_sign = op[0] ? a[31] && b[31] : a[31] || b[31];
    wire [31:0] ordered = zeros ? {zero_sign, 31'd0} : (less ^ op[0]) ? a : b;
    wire [31:0] minimum_maximum = an && bn ? 32'h7fc00000 : an ? b : bn ? a : ordered;
    assign result = minmax ? minimum_maximum : {31'd0, compare};
    assign predicate = compare;
    assign flags = {((an && !a[22]) || (bn && !b[22])), 4'd0};
endmodule
