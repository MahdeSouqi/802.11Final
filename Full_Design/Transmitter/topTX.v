`include "Scrambler/Scrambler.v"
`include "ConvEncoder/ConvEncoder.v"
`include "Interleaver/Interleaver.v"

module Transmitter(Start, Input, Reset, Clock, Clock2, Output);

    input wire Start;
    input wire Input;
    input wire Reset;
    input wire Clock;
    input wire Clock2;

    output wire Output;
    reg transmitter_out;
    reg is_scramble; //To determine wethher it should be scrambled or not!
    reg is_coded; //To determine wethher it should be encoded or not!

    //Scrambler Instatiation//////////////////////////////
    wire scrambler_out;
    reg scrambler_reset;
    reg scrambler_in;
    Scrambler scrambler(
        .Input(scrambler_in),
        .Reset(scrambler_reset),
        .Clock(Clock),
        .Output(scrambler_out)
    );

    //Parameters///////////////////////
    reg [3:0] CURRENT_STATE; //We defined it as a register as it will be changing....
    parameter [3:0] IDLE_STATE = 0;
    parameter [3:0] PLCP_PREAMBLE_STATE = 1;
    reg [7:0] TURNS_PLCP_PREAMBLE;
    parameter MAX_TURNS_PLCP_PREAMBLE = 95;
    parameter [0:8*12-1] PREAMBLE_SYMBOLS = {8'hAA, 8'hAA, 8'hAA, 8'hAA,
                                             8'hAA, 8'hAA, 8'hAA, 8'hAA,
                                             8'hAA, 8'hAA, 8'hAA, 8'hAA};

    parameter [3:0] SIGNAL_RATE_STATE = 2;
    reg [1:0] TURNS_RATE_STATE;
    parameter [0:3] RATE = 4'b1101;   
    parameter [3:0] SIGNAL_RESERVERD_STATE = 3;
    parameter [3:0] SIGNAL_LENGTH_STATE = 4;
    reg [3:0] TURNS_LENGTH_STATE;
    parameter [0:11] LENGTH = 12'h010;
    parameter [3:0] SIGNAL_PARITY_STATE = 5;
    parameter [3:0] SIGNAL_TAIL_STATE = 6;
    reg [2:0] TURNS_TAIL_STATE;



    parameter [3:0] DATA_SERVICE_STATE = 7;
    reg [3:0] TURNS_SERVICE_STATE;
    parameter [3:0] DATA_PSDU_STATE = 8;
    reg [14:0] TURNS_PSDU_STATE;            
    parameter [3:0] DATA_TAIL_STATE = 9;
    parameter [3:0] DATA_PADBITS_STATE = 10;
    parameter [7:0] N_DBPS = 24;
    parameter [8:0] N_CBPS = N_DBPS * 2; 
    reg [7:0] DPBS_REMAINDER;     
    reg [7:0] TURNS_PADBITS_STATE;

    parameter [3:0] WAIT4INTER_STATE = 11;  //Waiting-for-the-interleaver state
    reg [8:0] TURNS_WAIT4INTER_STATE;
    
    //  ConvEncoder Instatiation://////////////////////////
    wire encoder_out;
    reg encoder_reset;
    wire encoder_in;
    //      If we were in DATA frame scrambler out should be coded else transmitter out
    //Only the data part will be coded
    assign encoder_in = (CURRENT_STATE >= DATA_SERVICE_STATE) ? scrambler_out : transmitter_out;
    ConvEncoder convencoder(
        .Input(encoder_in),
        .Reset(encoder_reset),
        .Clock(Clock2),
        .Output(encoder_out)
    );


    //  Interleaver Instantiation:
    wire interleaver_out;
    reg interleaver_reset;

    always @(posedge Clock2)
    begin
        if (encoder_reset)
            interleaver_reset <= 1'b1;
        else
            interleaver_reset <= 1'b0;
    end
    Interleaver interleaver(
        .Input(encoder_out),
        .Clock(Clock2),
        .Reset(interleaver_reset),
        .Output(interleaver_out)
    );


    //  Output MUX:
    assign Output = is_coded ? interleaver_out : transmitter_out;


    //  FSM
    always @(posedge Clock, posedge Reset)
    begin
        if (Reset)      //  Reset State
        begin
            scrambler_reset <= 1'b1;
            encoder_reset <= 1'b1;
            scrambler_in <= 1'b0;
            transmitter_out <= 1'b0;
            is_scramble <= 1'b0;
            is_coded <= 1'b0;
            CURRENT_STATE <= IDLE_STATE; 
            TURNS_PLCP_PREAMBLE <= 8'h00;
            TURNS_RATE_STATE <= 2'b00;
            TURNS_LENGTH_STATE <= 4'h0;
            TURNS_TAIL_STATE <= 3'b000;
            TURNS_SERVICE_STATE <= 4'b0000;
            TURNS_PSDU_STATE <= 15'b000_0000_0000_0000;
            DPBS_REMAINDER <= 8'h00;
            TURNS_PADBITS_STATE <= 8'h00;
            TURNS_WAIT4INTER_STATE <= 8'h00;
        end
        else if (Start) //  Start State
        begin
            CURRENT_STATE <= PLCP_PREAMBLE_STATE;
            is_scramble <= 1'b0;
            is_coded <= 1'b0;
            transmitter_out <= 1'b0;
            scrambler_reset <= 1'b0;
            encoder_reset <= 1'b0;
            DPBS_REMAINDER <= 8'h00;
        end
        else
        begin
            case (CURRENT_STATE)
                //          PLCP_PREAMBLE::START
                PLCP_PREAMBLE_STATE:
                begin
                    is_scramble <= 1'b0;
                    transmitter_out <= PREAMBLE_SYMBOLS[TURNS_PLCP_PREAMBLE];

                    //  Reached to the end of PLCP sub-frame
                    if (TURNS_PLCP_PREAMBLE >= MAX_TURNS_PLCP_PREAMBLE)
                    begin
                        CURRENT_STATE <= SIGNAL_RATE_STATE;
                        TURNS_PLCP_PREAMBLE <= 8'h00;
                        encoder_reset <= 1'b1;
                    end
                    else
                        TURNS_PLCP_PREAMBLE <= TURNS_PLCP_PREAMBLE + 8'h01;
                end
                //  PLCP_PREAMBLE::END     SIGNAL::START
                SIGNAL_RATE_STATE:
                begin
                    encoder_reset <= 1'b0;
                    is_scramble <= 1'b0;
                    is_coded <= 1'b1;
                    transmitter_out <= RATE[TURNS_RATE_STATE];

                    //  Reached to the end of Rate sub-frame
                    if (TURNS_RATE_STATE == 2'b11)
                    begin
                        CURRENT_STATE <= SIGNAL_RESERVERD_STATE;
                        TURNS_RATE_STATE <= 2'b00;
                    end
                    else
                        TURNS_RATE_STATE <= TURNS_RATE_STATE + 2'b01;
                end
                SIGNAL_RESERVERD_STATE:
                begin
                    is_scramble <= 1'b0;
                    transmitter_out <= 1'b0;    //  Reserver bit

                    CURRENT_STATE <= SIGNAL_LENGTH_STATE;
                end
                SIGNAL_LENGTH_STATE:
                begin
                    is_scramble <= 1'b0;
                    transmitter_out <= LENGTH[TURNS_LENGTH_STATE];

                    //  Reached to the end of lenght sub-frame
                    if (TURNS_LENGTH_STATE >= 11)   //  12 - 1
                    begin
                        CURRENT_STATE <= SIGNAL_PARITY_STATE;
                        TURNS_LENGTH_STATE <= 2'b00;
                    end
                    else
                        TURNS_LENGTH_STATE <= TURNS_LENGTH_STATE + 2'b01;
                end
                SIGNAL_PARITY_STATE:
                begin
                    is_scramble <= 1'b0;
                    //  Calculate even parity of 0-16 bits
                    transmitter_out <= ^{ {RATE},   //  4  bits Data Rate
                                          {1'b0},   //  1  bit Reserved
                                          {LENGTH}  //  12 bits Data LENGTH
                                        };

                    //  Reached to the end of Parity sub-frame
                    CURRENT_STATE <= SIGNAL_TAIL_STATE;
                end
                SIGNAL_TAIL_STATE:
                begin
                    is_scramble <= 1'b0;
                    transmitter_out <= 1'b0;        //  =0 Tail bit

                    //  Reached to the end of tail sub-frame
                    if (TURNS_TAIL_STATE >= 5)      //  6 - 1
                    begin
                        CURRENT_STATE <= DATA_SERVICE_STATE;
                        TURNS_TAIL_STATE <= 3'b000;
                        scrambler_reset <= 1'b1;    //  Reseting Scrambler
                    end
                    else
                        TURNS_TAIL_STATE <= TURNS_TAIL_STATE + 3'b001;
                end
                //  SIGNAL::END             DATA::START
                DATA_SERVICE_STATE:
                begin
                    scrambler_reset <= 1'b0;
                    is_scramble <= 1'b1;
                    scrambler_in <= 1'b0;

                    //  Pad bits:
                    if (DPBS_REMAINDER == N_DBPS)
                        DPBS_REMAINDER <= 8'h01;
                    else
                        DPBS_REMAINDER <= DPBS_REMAINDER + 8'h01;

                    //  Reached to the end of service sub-frame
                    if (TURNS_SERVICE_STATE >= 15)
                    begin
                        CURRENT_STATE <= DATA_PSDU_STATE;
                        TURNS_SERVICE_STATE <= 4'b0000;
                    end
                    else
                        TURNS_SERVICE_STATE <= TURNS_SERVICE_STATE + 4'b0001;
                end
                DATA_PSDU_STATE:
                begin
                    is_scramble <= 1'b1;
                    scrambler_in <= Input;

                    //  Pad bits:
                    if (DPBS_REMAINDER == N_DBPS)
                        DPBS_REMAINDER <= 8'h01;
                    else
                        DPBS_REMAINDER <= DPBS_REMAINDER + 8'h01;

                    //  Reached to the end of psdu sub-frame (LENGHT bytes = LENGHT << 3 bits)
                    if (TURNS_PSDU_STATE + 15'b000_0000_0000_0001 >= {{LENGTH}, {3'b000}})
                    begin
                        CURRENT_STATE <= DATA_TAIL_STATE;
                        TURNS_PSDU_STATE <= 15'b000_0000_0000_0000;
                    end
                    else
                        TURNS_PSDU_STATE <= TURNS_PSDU_STATE + 15'b000_0000_0000_0001;
                end
                DATA_TAIL_STATE:
                begin
                    is_scramble <= 1'b1;
                    scrambler_in <= 1'b0;        //  =0 Tail bit

                    //  Pad bits:
                    if (DPBS_REMAINDER == N_DBPS)
                        DPBS_REMAINDER <= 8'h01;
                    else
                        DPBS_REMAINDER <= DPBS_REMAINDER + 8'h01;

                    //  Reached to the end of tail sub-frame
                    if (TURNS_TAIL_STATE >= 6)
                    begin
                        CURRENT_STATE <= DATA_PADBITS_STATE;
                        TURNS_TAIL_STATE <= 3'b000;
                    end
                    else
                        TURNS_TAIL_STATE <= TURNS_TAIL_STATE + 3'b001;
                end
                DATA_PADBITS_STATE:
                begin
                    //  Pad bits:
                    //      END OF FRAME
                    if (DPBS_REMAINDER == N_DBPS)
                    begin
                        DPBS_REMAINDER <= 8'h00;
                        CURRENT_STATE <= WAIT4INTER_STATE;
                        transmitter_out <= 1'b0; 
                    end
                    else
                    begin
                        DPBS_REMAINDER <= DPBS_REMAINDER + 8'h01; 
                        is_scramble <= 1'b1;
                        scrambler_in <= 1'b0;
                    end
                end
                //               DATA::END
                WAIT4INTER_STATE:
                begin
                    //  Reached to the end of Interleaving state
                    if (TURNS_WAIT4INTER_STATE + 8'h01 >= N_CBPS)
                    begin
                        CURRENT_STATE <= IDLE_STATE;
                        TURNS_WAIT4INTER_STATE <= 8'h00;
                        is_scramble <= 1'b0;
                    end
                    else
                        TURNS_WAIT4INTER_STATE <= TURNS_WAIT4INTER_STATE + 8'h01;
                end
                default:
                begin
                    scrambler_reset <= 1'b0;
                    encoder_reset <= 1'b0;
                    transmitter_out <= 1'b0;
                    is_scramble <= 1'b0;
                    is_coded <= 1'b0;
                    CURRENT_STATE <= IDLE_STATE;
                    TURNS_PLCP_PREAMBLE <= 8'h00;
                    TURNS_RATE_STATE <= 2'b00;
                    TURNS_LENGTH_STATE <= 4'h0;
                    TURNS_TAIL_STATE <= 3'b000;
                    TURNS_SERVICE_STATE <= 4'b0000;
                    TURNS_PSDU_STATE <= 15'b000_0000_0000_0000;
                    DPBS_REMAINDER <= 8'h00;
                    TURNS_PADBITS_STATE <= 8'h00;
                    TURNS_WAIT4INTER_STATE <= 8'h00;
                end
            endcase
        end
    end
endmodule