module ConvEncoder(Input, Reset, Clock, Output);

    input wire Input;
    input wire Reset;
    input wire Clock;
    output wire Output;

    parameter INITIAL_STATE = 7'b0000000;

    reg [1:7] x;
    reg is_odd;

    always @(posedge Clock, posedge Reset)
    begin
        if (Reset)
        begin
           x <= INITIAL_STATE;
           is_odd <= 1'b0; 
        end
        else
        begin
            if (is_odd)
                is_odd <= 1'b0;
            else
            begin
                x <= {{Input}, {x[1:6]}};
                is_odd <= 1'b1; 
            end
        end
    end

    assign Output = is_odd ?
                    x[1] ^ x[3] ^ x[4] ^ x[6] ^ x[7] :
                    x[1] ^ x[2] ^ x[3] ^ x[4] ^ x[7] ;
endmodule