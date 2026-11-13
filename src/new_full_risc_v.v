Claude










































































































































Riscv single cycle · V
`timescale 1ns/1ps
 
//==============================================================
// RV32I Single-Cycle Processor
// Supports: R-type, OP-IMM, LOAD (lb/lh/lw/lbu/lhu),
//           STORE (sb/sh/sw), BRANCH (all 6), JAL, JALR,
//           LUI, AUIPC, FENCE (as NOP)
//==============================================================
 
 
//--------------------------------------------------------------
// ALU
//--------------------------------------------------------------
module alu (
    input      [31:0] a,
    input      [31:0] b,
    input      [3:0]  alu_sel,
    output reg [31:0] result,
    output            zero
);
 
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_AND  = 4'd2;
    localparam ALU_OR   = 4'd3;
    localparam ALU_XOR  = 4'd4;
    localparam ALU_SLT  = 4'd5;
    localparam ALU_SLTU = 4'd6;
    localparam ALU_SLL  = 4'd7;
    localparam ALU_SRL  = 4'd8;
    localparam ALU_SRA  = 4'd9;
    localparam ALU_PASB = 4'd10;   // result = b (used by LUI)
 
    always @(*) begin
        case (alu_sel)
            ALU_ADD : result = a + b;
            ALU_SUB : result = a - b;
            ALU_AND : result = a & b;
            ALU_OR  : result = a | b;
            ALU_XOR : result = a ^ b;
            ALU_SLT : result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU: result = (a < b) ? 32'd1 : 32'd0;
            ALU_SLL : result = a << b[4:0];
            ALU_SRL : result = a >> b[4:0];
            ALU_SRA : result = $signed(a) >>> b[4:0];
            ALU_PASB: result = b;
            default : result = 32'd0;
        endcase
    end
 
    assign zero = (result == 32'd0);
 
endmodule
 
 
//--------------------------------------------------------------
// Register File (x0 hardwired to zero)
//--------------------------------------------------------------
module reg_file (
    input         clk,
    input         rst,
    input  [4:0]  rs1,
    input  [4:0]  rs2,
    input  [4:0]  rd,
    input  [31:0] write_data,
    input         reg_write,
    output [31:0] read_data1,
    output [31:0] read_data2
);
 
    reg [31:0] registers [0:31];
    integer i;
 
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end
        else if (reg_write && rd != 5'd0) begin
            registers[rd] <= write_data;
        end
    end
 
    assign read_data1 = (rs1 == 5'd0) ? 32'd0 : registers[rs1];
    assign read_data2 = (rs2 == 5'd0) ? 32'd0 : registers[rs2];
 
endmodule
 
 
//--------------------------------------------------------------
// Program Counter
//--------------------------------------------------------------
module program_counter (
    input             clk,
    input             rst,
    input      [31:0] pc_next,
    output reg [31:0] pc_current
);
 
    always @(posedge clk or posedge rst) begin
        if (rst)
            pc_current <= 32'd0;
        else
            pc_current <= pc_next;
    end
 
endmodule
 
 
//--------------------------------------------------------------
// Instruction Memory (256 words)
// - If INIT_FILE is given, it is loaded with $readmemh
// - Otherwise a built-in test program is loaded
//--------------------------------------------------------------
module instruction_memory #(
    parameter INIT_FILE = ""
)(
    input  [31:0] pc,
    output [31:0] instruction
);
 
    reg [31:0] memory [0:255];
    integer i;
 
    initial begin
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'h00000013;           // NOP (addi x0,x0,0)
 
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, memory);
        end
        else begin
            memory[0]  = 32'h00500093; // addi  x1,x0,5
            memory[1]  = 32'h00700113; // addi  x2,x0,7
            memory[2]  = 32'h002081b3; // add   x3,x1,x2      -> 12
            memory[3]  = 32'h40218233; // sub   x4,x3,x2      -> 5
            memory[4]  = 32'h00302023; // sw    x3,0(x0)
            memory[5]  = 32'h00002283; // lw    x5,0(x0)      -> 12
            memory[6]  = 32'h00120463; // beq   x4,x1,+8      (taken)
            memory[7]  = 32'h06300313; // addi  x6,x0,99      (skipped)
            memory[8]  = 32'h00100393; // addi  x7,x0,1
            memory[9]  = 32'h0080046f; // jal   x8,+8         -> x8=0x28
            memory[10] = 32'h06300493; // addi  x9,x0,99      (skipped)
            memory[11] = 32'h12345537; // lui   x10,0x12345
            memory[12] = 32'h0041f593; // andi  x11,x3,4      -> 4
            memory[13] = 32'h00209613; // slli  x12,x1,2      -> 20
            memory[14] = 32'hff000693; // addi  x13,x0,-16
            memory[15] = 32'h4026d713; // srai  x14,x13,2     -> -4
            memory[16] = 32'h00001797; // auipc x15,1         -> 0x1040
            memory[17] = 32'h00d00223; // sb    x13,4(x0)
            memory[18] = 32'h00400803; // lb    x16,4(x0)     -> -16
            memory[19] = 32'h00404883; // lbu   x17,4(x0)     -> 0xF0
            memory[20] = 32'h05400913; // addi  x18,x0,0x54
            memory[21] = 32'h008909e7; // jalr  x19,8(x18)    -> pc=0x5c, x19=0x58
            memory[22] = 32'h06300a13; // addi  x20,x0,99     (skipped)
            memory[23] = 32'h00000063; // beq   x0,x0,0       (halt loop)
        end
    end
 
    // Word-aligned fetch; out-of-range addresses return NOP
    assign instruction = (pc[31:10] == 22'd0) ? memory[pc[9:2]] : 32'h00000013;
 
endmodule
 
 
//--------------------------------------------------------------
// Data Memory (1 KB, byte addressable, little endian)
// funct3: 000 LB/SB, 001 LH/SH, 010 LW/SW, 100 LBU, 101 LHU
//--------------------------------------------------------------
module data_memory (
    input         clk,
    input         mem_read,
    input         mem_write,
    input  [2:0]  funct3,
    input  [31:0] addr,
    input  [31:0] write_data,
    output reg [31:0] read_data
);
 
    reg [31:0] mem [0:255];
    integer i;
 
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 32'd0;
    end
 
    wire [7:0]  widx = addr[9:2];
    wire [31:0] word = mem[widx];
 
    // ---------------- Read (combinational) ----------------
    reg [7:0]  b;
    reg [15:0] h;
 
    always @(*) begin
        case (addr[1:0])
            2'd0: b = word[7:0];
            2'd1: b = word[15:8];
            2'd2: b = word[23:16];
            default: b = word[31:24];
        endcase
        h = addr[1] ? word[31:16] : word[15:0];
 
        read_data = 32'd0;
        if (mem_read) begin
            case (funct3)
                3'b000: read_data = {{24{b[7]}},  b};   // LB
                3'b001: read_data = {{16{h[15]}}, h};   // LH
                3'b010: read_data = word;               // LW
                3'b100: read_data = {24'd0, b};         // LBU
                3'b101: read_data = {16'd0, h};         // LHU
                default: read_data = 32'd0;
            endcase
        end
    end
 
    // ---------------- Write (synchronous) ----------------
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000: begin                           // SB
                    case (addr[1:0])
                        2'd0: mem[widx][7:0]   <= write_data[7:0];
                        2'd1: mem[widx][15:8]  <= write_data[7:0];
                        2'd2: mem[widx][23:16] <= write_data[7:0];
                        2'd3: mem[widx][31:24] <= write_data[7:0];
                    endcase
                end
                3'b001: begin                           // SH
                    if (addr[1]) mem[widx][31:16] <= write_data[15:0];
                    else         mem[widx][15:0]  <= write_data[15:0];
                end
                3'b010: mem[widx] <= write_data;        // SW
                default: ;
            endcase
        end
    end
 
endmodule
 
 
//--------------------------------------------------------------
// Instruction Decoder
//--------------------------------------------------------------
module instruction_decoder (
    input  [31:0] instruction,
    output [6:0]  opcode,
    output [4:0]  rd,
    output [2:0]  funct3,
    output [4:0]  rs1,
    output [4:0]  rs2,
    output [6:0]  funct7
);
 
    assign opcode = instruction[6:0];
    assign rd     = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign rs1    = instruction[19:15];
    assign rs2    = instruction[24:20];
    assign funct7 = instruction[31:25];
 
endmodule
 
 
//--------------------------------------------------------------
// Control Unit
// wb_sel : 00 = ALU result, 01 = data memory, 10 = PC + 4
// a_sel  : 0 = rs1, 1 = PC (AUIPC)
// alu_src: 0 = rs2, 1 = immediate
//--------------------------------------------------------------
module control_unit (
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,
 
    output reg [3:0] alu_sel,
    output reg       reg_write,
    output reg       alu_src,
    output reg       a_sel,
    output reg       mem_read,
    output reg       mem_write,
    output reg [1:0] wb_sel,
    output reg       branch,
    output reg       jump,      // JAL
    output reg       jalr,      // JALR
    output reg       illegal
);
 
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_AND  = 4'd2;
    localparam ALU_OR   = 4'd3;
    localparam ALU_XOR  = 4'd4;
    localparam ALU_SLT  = 4'd5;
    localparam ALU_SLTU = 4'd6;
    localparam ALU_SLL  = 4'd7;
    localparam ALU_SRL  = 4'd8;
    localparam ALU_SRA  = 4'd9;
    localparam ALU_PASB = 4'd10;
 
    localparam OP_RTYPE  = 7'b0110011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_FENCE  = 7'b0001111;
 
    always @(*) begin
        // Defaults (safe NOP-like behaviour)
        alu_sel   = ALU_ADD;
        reg_write = 1'b0;
        alu_src   = 1'b0;
        a_sel     = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        wb_sel    = 2'b00;
        branch    = 1'b0;
        jump      = 1'b0;
        jalr      = 1'b0;
        illegal   = 1'b0;
 
        case (opcode)
 
            // ---------------- R-type ----------------
            OP_RTYPE: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000: begin
                        if      (funct7 == 7'b0000000) alu_sel = ALU_ADD;
                        else if (funct7 == 7'b0100000) alu_sel = ALU_SUB;
                        else illegal = 1'b1;
                    end
                    3'b001: begin alu_sel = ALU_SLL;  illegal = (funct7 != 7'b0000000); end
                    3'b010: begin alu_sel = ALU_SLT;  illegal = (funct7 != 7'b0000000); end
                    3'b011: begin alu_sel = ALU_SLTU; illegal = (funct7 != 7'b0000000); end
                    3'b100: begin alu_sel = ALU_XOR;  illegal = (funct7 != 7'b0000000); end
                    3'b101: begin
                        if      (funct7 == 7'b0000000) alu_sel = ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_sel = ALU_SRA;
                        else illegal = 1'b1;
                    end
                    3'b110: begin alu_sel = ALU_OR;   illegal = (funct7 != 7'b0000000); end
                    3'b111: begin alu_sel = ALU_AND;  illegal = (funct7 != 7'b0000000); end
                endcase
            end
 
            // ---------------- OP-IMM ----------------
            OP_IMM: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                case (funct3)
                    3'b000: alu_sel = ALU_ADD;    // ADDI
                    3'b010: alu_sel = ALU_SLT;    // SLTI
                    3'b011: alu_sel = ALU_SLTU;   // SLTIU
                    3'b100: alu_sel = ALU_XOR;    // XORI
                    3'b110: alu_sel = ALU_OR;     // ORI
                    3'b111: alu_sel = ALU_AND;    // ANDI
                    3'b001: begin                 // SLLI
                        alu_sel = ALU_SLL;
                        illegal = (funct7 != 7'b0000000);
                    end
                    3'b101: begin                 // SRLI / SRAI
                        if      (funct7 == 7'b0000000) alu_sel = ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_sel = ALU_SRA;
                        else illegal = 1'b1;
                    end
                endcase
            end
 
            // ---------------- LOAD ----------------
            OP_LOAD: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_read  = 1'b1;
                wb_sel    = 2'b01;
                alu_sel   = ALU_ADD;
                if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111)
                    illegal = 1'b1;
            end
 
            // ---------------- STORE ----------------
            OP_STORE: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_sel   = ALU_ADD;
                if (funct3 > 3'b010)
                    illegal = 1'b1;
            end
 
            // ---------------- BRANCH ----------------
            OP_BRANCH: begin
                branch = 1'b1;
                if (funct3 == 3'b010 || funct3 == 3'b011)
                    illegal = 1'b1;
            end
 
            // ---------------- JAL ----------------
            OP_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                wb_sel    = 2'b10;
            end
 
            // ---------------- JALR ----------------
            OP_JALR: begin
                reg_write = 1'b1;
                jalr      = 1'b1;
                alu_src   = 1'b1;
                alu_sel   = ALU_ADD;
                wb_sel    = 2'b10;
                if (funct3 != 3'b000)
                    illegal = 1'b1;
            end
 
            // ---------------- LUI ----------------
            OP_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_sel   = ALU_PASB;
            end
 
            // ---------------- AUIPC ----------------
            OP_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                a_sel     = 1'b1;
                alu_sel   = ALU_ADD;
            end
 
            // ---------------- FENCE (NOP) ----------------
            OP_FENCE: begin
            end
 
            default: illegal = 1'b1;
        endcase
    end
 
endmodule
 
 
//--------------------------------------------------------------
// Immediate Generator (I, S, B, U, J)
//--------------------------------------------------------------
module immediate_generator (
    input      [31:0] instruction,
    output reg [31:0] imm_out
);
 
    wire [6:0] opcode = instruction[6:0];
 
    always @(*) begin
        case (opcode)
 
            // I-type: OP-IMM, LOAD, JALR
            7'b0010011,
            7'b0000011,
            7'b1100111:
                imm_out = {{20{instruction[31]}}, instruction[31:20]};
 
            // S-type
            7'b0100011:
                imm_out = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
 
            // B-type
            7'b1100011:
                imm_out = {{19{instruction[31]}}, instruction[31], instruction[7],
                           instruction[30:25], instruction[11:8], 1'b0};
 
            // U-type: LUI, AUIPC
            7'b0110111,
            7'b0010111:
                imm_out = {instruction[31:12], 12'd0};
 
            // J-type: JAL
            7'b1101111:
                imm_out = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                           instruction[20], instruction[30:21], 1'b0};
 
            default:
                imm_out = 32'd0;
        endcase
    end
 
endmodule
 
 
//--------------------------------------------------------------
// Branch Comparator
//--------------------------------------------------------------
module branch_unit (
    input      [2:0]  funct3,
    input      [31:0] a,
    input      [31:0] b,
    output reg        take
);
 
    always @(*) begin
        case (funct3)
            3'b000: take = (a == b);                        // BEQ
            3'b001: take = (a != b);                        // BNE
            3'b100: take = ($signed(a) <  $signed(b));      // BLT
            3'b101: take = ($signed(a) >= $signed(b));      // BGE
            3'b110: take = (a <  b);                        // BLTU
            3'b111: take = (a >= b);                        // BGEU
            default: take = 1'b0;
        endcase
    end
 
endmodule
 
 
//--------------------------------------------------------------
// Datapath (top level)
//--------------------------------------------------------------
module datapath #(
    parameter INIT_FILE = ""
)(
    input  clk,
    input  rst,
    output illegal_instr
);
 
    // PC
    wire [31:0] pc_current, pc_next, pc_plus4, pc_target, jalr_target;
 
    // Instruction + fields
    wire [31:0] instruction;
    wire [6:0]  opcode, funct7;
    wire [4:0]  rd, rs1, rs2;
    wire [2:0]  funct3;
 
    // Control
    wire [3:0]  alu_sel;
    wire        reg_write, alu_src, a_sel;
    wire        mem_read, mem_write;
    wire [1:0]  wb_sel;
    wire        branch, jump, jalr;
 
    // Data
    wire [31:0] rd1, rd2, imm_out;
    wire [31:0] alu_a, alu_b, alu_result;
    wire        zero;
    wire [31:0] mem_read_data;
    reg  [31:0] write_back;
    wire        branch_take;
 
    // ---------------- Next-PC logic ----------------
    assign pc_plus4    = pc_current + 32'd4;
    assign pc_target   = pc_current + imm_out;                  // branch / JAL
    assign jalr_target = {alu_result[31:1], 1'b0};              // (rs1 + imm) & ~1
 
    assign pc_next = jalr                          ? jalr_target :
                     (jump | (branch & branch_take)) ? pc_target   :
                                                       pc_plus4;
 
    program_counter pc (
        .clk(clk), .rst(rst),
        .pc_next(pc_next), .pc_current(pc_current)
    );
 
    instruction_memory #(.INIT_FILE(INIT_FILE)) imem (
        .pc(pc_current), .instruction(instruction)
    );
 
    instruction_decoder decoder (
        .instruction(instruction),
        .opcode(opcode), .rd(rd), .funct3(funct3),
        .rs1(rs1), .rs2(rs2), .funct7(funct7)
    );
 
    control_unit control (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .alu_sel(alu_sel), .reg_write(reg_write), .alu_src(alu_src),
        .a_sel(a_sel), .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel(wb_sel), .branch(branch), .jump(jump), .jalr(jalr),
        .illegal(illegal_instr)
    );
 
    immediate_generator imm_gen (
        .instruction(instruction), .imm_out(imm_out)
    );
 
    reg_file rf (
        .clk(clk), .rst(rst),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .write_data(write_back), .reg_write(reg_write),
        .read_data1(rd1), .read_data2(rd2)
    );
 
    // ---------------- ALU operand muxes ----------------
    assign alu_a = a_sel   ? pc_current : rd1;
    assign alu_b = alu_src ? imm_out    : rd2;
 
    alu alu_inst (
        .a(alu_a), .b(alu_b), .alu_sel(alu_sel),
        .result(alu_result), .zero(zero)
    );
 
    branch_unit bru (
        .funct3(funct3), .a(rd1), .b(rd2), .take(branch_take)
    );
 
    data_memory dmem (
        .clk(clk),
        .mem_read(mem_read), .mem_write(mem_write),
        .funct3(funct3),
        .addr(alu_result),
        .write_data(rd2),
        .read_data(mem_read_data)
    );
 
    // ---------------- Write-back mux ----------------
    always @(*) begin
        case (wb_sel)
            2'b00:   write_back = alu_result;
            2'b01:   write_back = mem_read_data;
            2'b10:   write_back = pc_plus4;
            default: write_back = alu_result;
        endcase
    end
 
endmodule
 
Claude finished the response
