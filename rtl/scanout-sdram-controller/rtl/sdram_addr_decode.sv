module sdram_addr_decode #(
    parameter integer MAPPING = 5
) (
    input  logic [26:0] byte_address,
    output logic        chip,
    output logic [1:0]  bank,
    output logic [12:0] row,
    output logic [9:0]  column,
    output logic        byte_select,
    output logic [10:0] contiguous_words
);
    // Mappings match tools/sdram-model. Mapping 5 is stripe-1k-bank-chip.
    always_comb begin
        byte_select = byte_address[0];
        chip = 1'b0;
        bank = 2'b00;
        row = 13'b0;
        column = 10'b0;
        contiguous_words = 11'd1024 - {1'b0,byte_address[10:1]};
        case (MAPPING)
            0: begin // row-chip-bank-column
                column = byte_address[10:1]; bank = byte_address[12:11];
                chip = byte_address[13]; row = byte_address[26:14];
            end
            1: begin // row-bank-chip-column
                column = byte_address[10:1]; chip = byte_address[11];
                bank = byte_address[13:12]; row = byte_address[26:14];
            end
            2: begin // linear: chip, bank, row, column
                column = byte_address[10:1]; row = byte_address[23:11];
                bank = byte_address[25:24]; chip = byte_address[26];
            end
            3: begin // chip-row-bank-column
                column = byte_address[10:1]; bank = byte_address[12:11];
                row = byte_address[25:13]; chip = byte_address[26];
            end
            4: begin // stripe-1k-chip-bank
                column = {byte_address[13], byte_address[9:1]};
                bank = byte_address[11:10]; chip = byte_address[12];
                row = byte_address[26:14];
                contiguous_words = 11'd512 - {2'b0,byte_address[9:1]};
            end
            default: begin // stripe-1k-bank-chip
                column = {byte_address[13], byte_address[9:1]};
                chip = byte_address[10]; bank = byte_address[12:11];
                row = byte_address[26:14];
                contiguous_words = 11'd512 - {2'b0,byte_address[9:1]};
            end
        endcase
    end

    initial begin
        if (MAPPING < 0 || MAPPING > 5) $error("unsupported SDRAM mapping");
    end
endmodule
