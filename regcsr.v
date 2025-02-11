`include "mycpu.h"

module regcsr(
    input  wire        clk       ,
    input  wire        reset     ,

    input  wire        csr_we    , //写使能
    input  wire [13:0] csr_num   , //寄存器号
    input  wire [31:0] csr_wmask , //写掩码
    input  wire [31:0] csr_wvalue, //写数据
    output wire [31:0] csr_rvalue, //读返回值
 
    input  wire        ertn_flush, //ertn执行有效信号
    input  wire        wb_ex     , //写回流水级异常
    input  wire [ 5:0] wb_ecode  , //异常类型
    input  wire        wb_esubcode,//
    input  wire [31:0] wb_pc     , //!!!!
    input  wire [31:0] wb_vaddr  , //访存虚地址

    output wire [31:0] ex_entry  , //to pre-IF, 异常处理入口地址
    output wire [31:0] ex_era    ,
    output wire        has_int   , //to id, 中断有效信号
    // counter
    output wire [63:0] counter   ,
    output wire [31:0] counter_id
);

reg  [ 1:0] csr_crmd_plv;     //priority level
reg         csr_crmd_ie;      //interrupt enable
reg         csr_crmd_da;      //direct address enable
reg         csr_crmd_pg;      //mapping address enable
reg  [ 1:0] csr_crmd_datf;    //in direct address
reg  [ 1:0] csr_crmd_datm;    //in direct address
reg  [ 1:0] csr_prmd_pplv;
reg         csr_prmd_pie;
reg  [12:0] csr_ecfg_lie;
reg  [12:0] csr_estat_is;
reg  [ 5:0] csr_estat_ecode;
reg  [ 8:0] csr_estat_esubcode;
reg  [31:0] csr_era_pc;
reg  [25:0] csr_eentry_va;
reg  [31:0] csr_save0_data;
reg  [31:0] csr_save1_data;
reg  [31:0] csr_save2_data;
reg  [31:0] csr_save3_data;

// Add in lab 9
reg  [31:0] csr_badv_vaddr;
reg  [31:0] csr_tid_tid;
reg         csr_tcfg_en;
reg         csr_tcfg_periodic;
reg  [29:0] csr_tcfg_initval;
wire [31:0] tcfg_next_value;
wire [31:0] csr_tval;
reg  [31:0] timer_cnt;
wire        csr_ticlr_clr;
wire        wb_ex_addr_err; 

always @(posedge clk) begin
    if(reset) begin
        csr_crmd_plv <= 2'b0; //highest priority level
        csr_crmd_ie  <= 1'b0;
        csr_crmd_da  <= 1'b1;//!
        csr_crmd_pg  <= 1'b0;
        csr_crmd_datf<= 2'b0;
        csr_crmd_datm<= 2'b0;
    end
    else if(wb_ex) begin
        csr_crmd_plv <= 2'b0; //when exception happens, set highest priority level
        csr_crmd_ie  <= 1'b0; //when exception happens, set interrupt disenble, to mask interrupt
    end
    else if(ertn_flush) begin
        csr_crmd_plv <= csr_prmd_pplv; //when ERTN, recover pplv
        csr_crmd_ie  <= csr_prmd_pie;  //when ERTN, recover pie
    end
    else if(csr_we && csr_num==`CSR_CRMD) begin //csrwr, csrxchg
        csr_crmd_plv <= csr_wmask[`CSR_CRMD_PLV] & csr_wvalue[`CSR_CRMD_PLV]
                     | ~csr_wmask[`CSR_CRMD_PLV] & csr_crmd_plv;
        csr_crmd_ie  <= csr_wmask[`CSR_CRMD_IE] & csr_wvalue[`CSR_CRMD_IE]
                     | ~csr_wmask[`CSR_CRMD_IE] & csr_crmd_ie;
        csr_crmd_da  <= csr_wmask[`CSR_CRMD_DA] & csr_wvalue[`CSR_CRMD_DA]
                     | ~csr_wmask[`CSR_CRMD_DA] & csr_crmd_da;
        csr_crmd_pg  <= csr_wmask[`CSR_CRMD_PG] & csr_wvalue[`CSR_CRMD_PG]
                     | ~csr_wmask[`CSR_CRMD_PG] & csr_crmd_pg;
        csr_crmd_datf <= csr_wmask[`CSR_CRMD_DATF] & csr_wvalue[`CSR_CRMD_DATF]
                     | ~csr_wmask[`CSR_CRMD_DATF] & csr_crmd_datf;
        csr_crmd_datm <= csr_wmask[`CSR_CRMD_DATM] & csr_wvalue[`CSR_CRMD_DATM]
                     | ~csr_wmask[`CSR_CRMD_DATM] & csr_crmd_datm;                    
    end
end

wire [31:0] csr_crmd_rvalue = {23'b0,         //31:9
                               csr_crmd_datm, //8:7
                               csr_crmd_datf, //6:5
                               csr_crmd_pg,   //4
                               csr_crmd_da,   //3
                               csr_crmd_ie,   //2
                               csr_crmd_plv   //1:0
                              };

always @(posedge clk) begin
    if(reset) begin
        csr_prmd_pplv <= 2'b0; //when exception happens, save context
        csr_prmd_pie  <= 1'b0;
    end
    if(wb_ex && csr_crmd_rvalue[2:0]!=3'b000) begin //!!!
        csr_prmd_pplv <= csr_crmd_plv; //when exception happens, save context
        csr_prmd_pie  <= csr_crmd_ie ;
    end
    else if(csr_we && csr_num==`CSR_PRMD) begin
        csr_prmd_pplv <= csr_wmask[`CSR_PRMD_PPLV] & csr_wvalue[`CSR_PRMD_PPLV]
                      | ~csr_wmask[`CSR_PRMD_PPLV] & csr_prmd_pplv;
        csr_prmd_pie  <= csr_wmask[`CSR_PRMD_PIE]  & csr_wvalue[`CSR_PRMD_PIE]
                      | ~csr_wmask[`CSR_PRMD_PIE]  & csr_prmd_pie;
    end
end

wire [31:0] csr_prmd_rvalue = {29'b0        , //31:3
                               csr_prmd_pie , //2
                               csr_prmd_pplv  //1:0
                              };

always @ (posedge clk) begin
    if (reset) 
        csr_ecfg_lie <= 13'b0;
    else if(csr_we && csr_num == `CSR_ECFG) 
        csr_ecfg_lie <= csr_wmask[`CSR_ECFG_LIE] & csr_wvalue[`CSR_ECFG_LIE]
                     | ~csr_wmask[`CSR_ECFG_LIE] & csr_ecfg_lie;
end


wire [31:0] csr_ecfg_rvalue = {19'b0,          //31:13
                               csr_ecfg_lie    //12:0
                              };

always @(posedge clk) begin
    if(reset)
        csr_estat_is[1:0] <= 2'b0;
    else if(csr_we && csr_num==`CSR_ESTAT)
        csr_estat_is[1:0] <= csr_wmask[`CSR_ESTAT_IS10] & csr_wvalue[`CSR_ESTAT_IS10]
                          | ~csr_wmask[`CSR_ESTAT_IS10] & csr_estat_is[1:0];
    
    csr_estat_is[9:2] <= 8'b0;//hw_int_in[7:0];//hardware interrupt
    csr_estat_is[10]  <= 1'b0;          //no define

    if (csr_tcfg_en && timer_cnt[31:0]==32'b0)
        csr_estat_is[11] <= 1'b1; //timer interrupt
    else if (csr_we && csr_num==`CSR_TICLR && csr_wmask[`CSR_TICLR_CLR] && csr_wvalue[`CSR_TICLR_CLR])
        csr_estat_is[11] <= 1'b0; // Finish in lab 9

    csr_estat_is[12] <= 1'b0;//ipi_int_in; //ipi interrupt
end

always @(posedge clk) begin
    if(wb_ex & ~ertn_flush) begin
        csr_estat_ecode    <= wb_ecode;
        csr_estat_esubcode <= wb_esubcode;
    end
end

wire [31:0] csr_estat_rvalue = {1'b0              , //31
                                csr_estat_esubcode, //30:22
                                csr_estat_ecode   , //21:16, exception types
                                3'b0              , //15:13
                                csr_estat_is[12:2], //12:2,other interrupt
                                csr_estat_is[ 1:0]  //1:0, software interrupt
                               };

always @(posedge clk) begin
    if(reset)
        csr_era_pc <= 32'b0;
    else if(wb_ex & ~ertn_flush)
        csr_era_pc <= wb_pc;
    else if(csr_we && csr_num==`CSR_ERA)
        csr_era_pc <= csr_wmask[`CSR_ERA_PC] & csr_wvalue[`CSR_ERA_PC]
                   | ~csr_wmask[`CSR_ERA_PC] & csr_era_pc;
end

wire [31:0] csr_era_rvalue = csr_era_pc;
assign ex_era = csr_era_rvalue;

always @(posedge clk) begin
    if(csr_we && csr_num==`CSR_EENTRY)
        csr_eentry_va <= csr_wmask[`CSR_EENTRY_VA] & csr_wvalue[`CSR_EENTRY_VA]
                      | ~csr_wmask[`CSR_EENTRY_VA] & csr_eentry_va;
end

wire [31:0] csr_eentry_rvalue = {csr_eentry_va, //31:6
                                 6'b0           // 5:0
                                };//that is, the address must be xxx000000
                                
assign ex_entry = csr_eentry_rvalue;

always @(posedge clk) begin
    if (reset) begin
        csr_save0_data <= 32'b0;
        csr_save1_data <= 32'b0;
        csr_save2_data <= 32'b0;
        csr_save3_data <= 32'b0;
    end
    else if(csr_we && csr_num==`CSR_SAVE0)
        csr_save0_data <= csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                       | ~csr_wmask[`CSR_SAVE_DATA] & csr_save0_data;
    else if(csr_we && csr_num==`CSR_SAVE1)
        csr_save1_data <= csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                       | ~csr_wmask[`CSR_SAVE_DATA] & csr_save1_data;
    else if(csr_we && csr_num==`CSR_SAVE2)
        csr_save2_data <= csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                       | ~csr_wmask[`CSR_SAVE_DATA] & csr_save2_data;
    else if(csr_we && csr_num==`CSR_SAVE3)
        csr_save3_data <= csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                       | ~csr_wmask[`CSR_SAVE_DATA] & csr_save3_data;
end

wire [31:0]  csr_save0_rvalue = csr_save0_data;
wire [31:0]  csr_save1_rvalue = csr_save1_data;
wire [31:0]  csr_save2_rvalue = csr_save2_data;
wire [31:0]  csr_save3_rvalue = csr_save3_data;

// BADV
assign wb_ex_addr_err = wb_ecode == `ECODE_ADE || wb_ecode == `ECODE_ALE;

always @(posedge clk) begin
    if (wb_ex && wb_ex_addr_err)
        csr_badv_vaddr <= (wb_ecode == `ECODE_ADE && wb_esubcode == `ESUBCODE_ADEF) ? wb_pc : wb_vaddr;
end

wire [31:0] csr_badv_rvalue = csr_badv_vaddr;

// TID
always @(posedge clk) begin
    if (reset)
        csr_tid_tid <= 32'd0;
    else if (csr_we && csr_num == `CSR_TID)
        csr_tid_tid <= csr_wmask[`CSR_TID_TID] & csr_wvalue[`CSR_TID_TID] 
                    | ~csr_wmask[`CSR_TID_TID] & csr_tid_tid;
end

wire [31:0] csr_tid_rvalue = csr_tid_tid;

// TCFG
always @(posedge clk) begin
    if (reset)
        csr_tcfg_en <= 1'b0;
    else if (csr_we && csr_num == `CSR_TCFG)
        csr_tcfg_en <= csr_wmask[`CSR_TCFG_EN] & csr_wvalue[`CSR_TCFG_EN] |
                      ~csr_wmask[`CSR_TCFG_EN] & csr_tcfg_en;
                    
    if (csr_we && csr_num == `CSR_TCFG) begin
        csr_tcfg_periodic <= csr_wmask[`CSR_TCFG_PERIODIC] & csr_wvalue[`CSR_TCFG_PERIODIC] |
                            ~csr_wmask[`CSR_TCFG_PERIODIC] & csr_tcfg_periodic;
        csr_tcfg_initval  <= csr_wmask[`CSR_TCFG_INITVAL]  & csr_wvalue[`CSR_TCFG_INITVAL]  |
                            ~csr_wmask[`CSR_TCFG_INITVAL]  & csr_tcfg_initval;
    end
end

wire [31:0] csr_tcfg_rvalue = {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en};

// TVAL
assign tcfg_next_value = csr_wmask[31:0] & csr_wvalue[31:0] |
                        ~csr_wmask[31:0] & {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en};

always @(posedge clk) begin
    if (reset)
        timer_cnt <= 32'hffffffff;
    else if (csr_we && csr_num == `CSR_TCFG && tcfg_next_value[`CSR_TCFG_EN])
        timer_cnt <= {tcfg_next_value[`CSR_TCFG_INITVAL], 2'b0};
    else if (csr_tcfg_en && timer_cnt != 32'hffffffff) begin
        if (timer_cnt[31:0] == 32'b0 && csr_tcfg_periodic)
            timer_cnt <= {csr_tcfg_initval, 2'b0};
        else 
            timer_cnt <= timer_cnt - 1'b1;
    end
end

assign csr_tval = timer_cnt[31:0];


// TICLR
assign csr_ticlr_clr = 1'b0;

wire [31:0] csr_ticlr = {31'd0, csr_ticlr_clr};


assign csr_rvalue = {32{csr_num==`CSR_CRMD  }} & csr_crmd_rvalue
                  | {32{csr_num==`CSR_PRMD  }} & csr_prmd_rvalue
                  | {32{csr_num==`CSR_ESTAT }} & csr_estat_rvalue
                  | {32{csr_num==`CSR_ERA   }} & csr_era_rvalue
                  | {32{csr_num==`CSR_EENTRY}} & csr_eentry_rvalue
                  | {32{csr_num==`CSR_ECFG  }} & csr_ecfg_rvalue
                  | {32{csr_num==`CSR_SAVE0 }} & csr_save0_rvalue
                  | {32{csr_num==`CSR_SAVE1 }} & csr_save1_rvalue
                  | {32{csr_num==`CSR_SAVE2 }} & csr_save2_rvalue
                  | {32{csr_num==`CSR_SAVE3 }} & csr_save3_rvalue
                  | {32{csr_num==`CSR_BADV  }} & csr_badv_rvalue
                  | {32{csr_num==`CSR_TID   }} & csr_tid_rvalue
                  | {32{csr_num==`CSR_TCFG  }} & csr_tcfg_rvalue
                  | {32{csr_num==`CSR_TVAL  }} & csr_tval
                  | {32{csr_num==`CSR_TICLR }} & csr_ticlr;

assign has_int = ((csr_estat_is[12:0] & csr_ecfg_lie[12:0]) != 13'b0)
                && (csr_crmd_ie == 1'b1);

reg [63:0] cnt;
always @(posedge clk) begin
    if (reset)
        cnt <= 64'b0;
    else 
        cnt <= cnt + 1'b1;
end

assign counter = cnt;
assign counter_id = csr_tid_tid;

endmodule