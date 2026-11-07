module VX_ucc_bf16x9_prepare (
    input  wire [31:0]       a,
    input  wire [31:0]       b,
    input  wire [31:0]       c,
    input  wire [1:0]        op,
    output wire [8:0][10:0]  mul_a,
    output wire [8:0][10:0]  mul_b,
    input  wire [8:0][21:0]  products,
    output wire [16:0][9:0]  exponents,
    output wire [16:0][24:0] significands,
    output wire              zero_sign,
    output wire              special,
    output wire [31:0]       special_result,
    output wire [4:0]        flags
);
    wire [31:0] x = a;
    wire [31:0] y = op[1] ? 32'h3f800000 : b;
    wire psign = x[31] ^ y[31];
    wire [31:0] z = op[1] ? {b[31] ^ op[0], b[30:0]} : op[0] ? {psign, 31'd0} : c;
    wire [7:0] ex = x[30:23], ey = y[30:23], ez = z[30:23];
    wire [23:0] mx = {(|ex), x[22:0]}, my = {(|ey), y[22:0]}, mz = {(|ez), z[22:0]};
    wire xzero = !(|x[30:0]), yzero = !(|y[30:0]), zzero = !(|z[30:0]);
    wire xnan = (&ex) && (|x[22:0]), ynan = (&ey) && (|y[22:0]), znan = (&ez) && (|z[22:0]);
    wire xinf = (&ex) && !(|x[22:0]), yinf = (&ey) && !(|y[22:0]), zinf = (&ez) && !(|z[22:0]);
    wire snan = (xnan && !x[22]) || (ynan && !y[22]) || (znan && !z[22]);
    wire bad_product = (xinf && yzero) || (yinf && xzero);
    wire pinf = (xinf || yinf) && !(xnan || ynan || bad_product);
    wire invalid = snan || bad_product || (pinf && zinf && psign != z[31]);
    wire nan_result = xnan || ynan || znan || invalid;
    assign special = nan_result || pinf || zinf;
    assign special_result = nan_result ? 32'h7fc00000 : {pinf ? psign : z[31], 8'hff, 23'd0};
    assign flags = {invalid, 4'd0};
    assign zero_sign = (xzero || yzero) && zzero && (psign == z[31]) && psign;
    wire [9:0] xe = ex == 0 ? 10'd1 : 10'(ex);
    wire [9:0] ye = ey == 0 ? 10'd1 : 10'(ey);
    wire [9:0] ze = ez == 0 ? 10'd1 : 10'(ez);
    wire [9:0] product_exponent = xe + ye + 10'd8;
    for (genvar i = 0; i < 9; ++i) begin : g_product
        assign mul_a[i] = {3'd0, mx[(i/3)*8 +: 8]};
        assign mul_b[i] = {3'd0, my[(i%3)*8 +: 8]};
        assign exponents[i] = (|mul_a[i]) && (|mul_b[i])
                            ? product_exponent + 10'(8*((i/3)+(i%3))) : '0;
        assign significands[i] = {psign, products[i][15:0], 8'd0};
    end
    assign exponents[15:9] = '0;
    assign significands[15:9] = '0;
    assign exponents[16] = zzero ? 10'd0 : ze + 10'd167;
    assign significands[16] = {z[31], mz};
endmodule
