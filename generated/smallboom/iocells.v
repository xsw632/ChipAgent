// sky130hd IO Cell stubs for Chipyard compatibility
// Behavioral models for synthesis

// Generic Digital Input I/O Cell
module GenericDigitalInIOCell (
    inout pad,
    input  ie,
    output i
);
    assign i = ie ? pad : 1'b0;
endmodule

// Generic Digital Output I/O Cell  
module GenericDigitalOutIOCell (
    inout pad,
    input  o,
    input  oe
);
    assign pad = oe ? o : 1'bz;
endmodule

// Enhanced Integrated Clock Gate Cell
module EICG_wrapper (
    input clk,
    input e,
    input te,
    output q
);
    assign q = e ? clk : 1'b0;
endmodule

// Clock Divider
module ClockDividerN #(
    parameter DIV_WIDTH = 4
) (
    input clk,
    input rst,
    output reg div
);
    reg [DIV_WIDTH-1:0] counter;
    always @(posedge clk or posedge rst) begin
        if (rst) counter <= {DIV_WIDTH{1'b0}};
        else counter <= counter + 1'b1;
    end
    assign div = counter[DIV_WIDTH-1];
endmodule

// Plusarg reader with FORMAT and DEFAULT parameters
module plusarg_reader #(
    parameter FORMAT = "",
    parameter DEFAULT = 0,
    parameter WIDTH = 1
) (
    output reg [WIDTH-1:0] out
);
    initial out = DEFAULT[WIDTH-1:0];
endmodule
