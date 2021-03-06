// Clock freq : 100MHz 기준
// Baud rate  : 115200 bps
// Data bit   : 8 bits
// Parity bit : None
// stop bit   : 1 bit
// 이것도 동적으로 작성은 가능할 듯.

// UART Controller

`define PARITY_NONE  0
`define PARITY_ODD   1
`define PARITY_EVEN  2
`define PARITY_MARK  3
`define PARITY_SPACE 4

module UART_Controller # (
	parameter CLK_FREQ = 100000000, // parameter 작업 마저 해야 함
	parameter BAUD_RATE = 115200,
	parameter OVER_SAMPLES = 16,
	parameter DATA_BITS = 8,
	parameter PARITY = `PARITY_NONE,
	parameter STOP_BITS = 1
	)	(
	input wire clk, // E3
	output wire tx, // FPGA Tx D10 -> PC Rx
	input wire rx // PC Tx -> FPGA Rx A9
	);

	// reg write_en;
	// reg write_busy;
	// reg read_clear;
	// reg read_complete;
	// reg [DATA_BITS-1:0] data_in;
	// reg [DATA_BITS-1:0] data_out;

	// wire [DATA_BITS-1:0] data_to_write;
	// wire [DATA_BITS-1:0] data_read_from_uart;

	// assign data_to_write = data_out;

	wire [DATA_BITS-1:0] data_to_write;
	wire [DATA_BITS-1:0] data_read_from_uart; // PC -> rx -> data_read_from_uart -> data_to_write -> tx -> PC
	wire write_en; // 응답이 오면 닫는 걸로 바꿔야 함.
	wire write_busy;
	wire write_complete;
	wire read_clear;
	wire read_complete;

	UART # (
		.CLK_FREQ(CLK_FREQ),
		.BAUD_RATE(BAUD_RATE),
		.OVER_SAMPLES(OVER_SAMPLES),
		.DATA_BITS(DATA_BITS),
		.PARITY(PARITY),
		.STOP_BITS(STOP_BITS)
	) _UART (
		.clk(clk),
		.tx(tx),
		.rx(rx),
		.data_to_write(data_to_write),
		.data_read_from_uart(data_read_from_uart),
		.write_en(write_en),
		.write_busy(write_busy),
		.write_complete(write_complete),
		.read_clear(read_clear),
		.read_complete(read_complete)
	);

	// 앵무새 테스트벤치
	assign data_to_write = (!write_busy ? data_read_from_uart : data_to_write);
	assign write_en = write_complete;
	assign read_clear = read_complete;

	// initial
	// begin
		// write_en <= 1'b0;
		// write_busy <= 1'b0;
		// read_clear <= 1'b0;
		// read_complete <= 1'b0;
		// data_to_write <= 0;
		// data_read_from_uart <= 0;
	// end

	// 앵무새 테스트벤치
	// always @ (posedge clk)
	// begin
		// if (read_complete && !write_busy)
		// begin
			// data_out <= data_read_from_uart;
			// write_en <= 1'b1;
			// read_complete <= 1'b0;
		// end
	// end

endmodule

// UART Interface
module UART # (
	parameter CLK_FREQ = 100000000,
	parameter BAUD_RATE = 115200,
	parameter OVER_SAMPLES = 16,
	parameter DATA_BITS = 8,
	parameter PARITY = `PARITY_NONE,
	parameter STOP_BITS = 1
	)	(
	input wire clk,
	output reg tx,
	input wire rx,
	input wire [DATA_BITS-1:0] data_to_write,
	output wire [DATA_BITS-1:0] data_read_from_uart,
	input wire write_en,
	output wire write_busy,
	output wire write_complete,
	input wire read_clear,
	output wire read_complete
	);

	wire rx_clk_en;
	wire tx_clk_en;

	// Generate baud rate by dividing a 100MHz clock into a 115200 baud.
	// rx/tx pair where the rx clcken oversamples by 16x.
	localparam RX_ACC_MAX = CLK_FREQ / (BAUD_RATE * OVER_SAMPLES); // 54.253
	localparam TX_ACC_MAX = CLK_FREQ / BAUD_RATE; // 868.056
	localparam RX_ACC_WIDTH = $clog2(RX_ACC_MAX); // 5.762 = 6
	localparam TX_ACC_WIDTH = $clog2(TX_ACC_MAX); // 9.762 = 10

	localparam DATA_BIT_WIDTH = $clog2(DATA_BITS);
	localparam STOP_BIT_WIDTH = $clog2(STOP_BITS);

	reg [RX_ACC_WIDTH - 1:0] rx_acc = 0;
	reg [TX_ACC_WIDTH - 1:0] tx_acc = 0;

	assign rx_clk_en = (rx_acc == 0);
	assign tx_clk_en = (tx_acc == 0);

	// generate Rx tick
	always @ (posedge clk)
	begin
		if (rx_acc == RX_ACC_MAX[RX_ACC_WIDTH - 1:0])
		begin
			rx_acc <= 0;
		end
		else
		begin
			rx_acc <= rx_acc + 1;
		end
	end

	// generate Tx tick
	always @ (posedge clk)
	begin
		if (tx_acc == TX_ACC_MAX[TX_ACC_WIDTH - 1:0])
		begin
			tx_acc <= 0;
		end
		else
		begin
			tx_acc <= tx_acc + 1;
		end
	end

	// Tx
	initial
	begin
		 tx <= 1'b1;
	end

	localparam TX_STATE_READY = 3'b000;
	localparam TX_STATE_START = 3'b001;
	localparam TX_STATE_DATA = 3'b010;
	localparam TX_STATE_PARITY = 3'b011;
	localparam TX_STATE_STOP = 3'b100;
	localparam TX_STATE_FINISHED = 3'b101;

	reg [DATA_BITS-1:0] data = 0;
	reg [DATA_BIT_WIDTH-1:0] index_tx = 0;
	reg [($clog2(STOP_BIT_WIDTH) > 0 ? $clog2(STOP_BIT_WIDTH)-1 : 0):0] stop_cnt = 0;
	reg [1:0] state_tx = TX_STATE_READY;

	always @ (posedge clk)
	begin
		case (state_tx)
			TX_STATE_READY:
			begin
				if (write_en)
				begin
					state_tx <= TX_STATE_START;
					data <= data_to_write;
					index_tx <= 0;
				end
			end

			TX_STATE_START:
			begin
				if (tx_clk_en)
				begin
					tx <= 1'b0; // start bit
					state_tx <= TX_STATE_DATA;
				end
			end

			TX_STATE_DATA:
			begin
				if (tx_clk_en)
				begin
					if (index_tx == DATA_BIT_WIDTH - 1)
					begin
						state_tx <= TX_STATE_STOP;
					end
					else
					begin
						index_tx <= index_tx + 1;
					end
					tx <= data[index_tx];
				end
			end

			TX_STATE_PARITY:
			begin
				if (tx_clk_en)
				begin
					case (PARITY)
						`PARITY_NONE:;
						`PARITY_ODD:
						begin
							tx <= ~^data;
						end

						`PARITY_EVEN:
						begin
							tx <= ^data;
						end

						`PARITY_MARK:
						begin
							tx <= 1'b1; // mark bit = logic 1
						end

						`PARITY_SPACE:
						begin
							tx <= 1'b0; // space bit = logic 0
						end
						default:;
					endcase
					state_tx <= TX_STATE_STOP;
				end
			end

			TX_STATE_STOP:
			begin
				if (tx_clk_en)
				begin
					if (stop_cnt < STOP_BITS)
					begin
						tx <= 1'b1; // stop bit
						stop_cnt <= stop_cnt + 1;
					end
					else
					begin
						state_tx <= TX_STATE_FINISHED;
					end
				end
			end

			TX_STATE_FINISHED:
			begin
				// This state is to make sure that writing job has finished.
				state_tx <= TX_STATE_READY;
			end

			default:
			begin
				tx <= 1'b1;
				state_tx <= TX_STATE_READY;
			end
		endcase
	end

	assign write_busy = (state_tx != TX_STATE_READY);
	assign write_complete = (state_tx == TX_STATE_FINISHED);

	// Rx
	initial
	begin
		data <= 0;
	end

	localparam RX_STATE_START = 2'b00;
	localparam RX_STATE_DATA = 2'b01;
	localparam RX_STATE_STOP = 2'b10;
	localparam RX_STATE_FINISHED = 2'b11;

	reg [OVER_SAMPLES-1:0] sample = 0;
	reg [OVER_SAMPLES-1:0] index_rx = 0;
	reg [2*OVER_SAMPLES-1:0] scratch = 0;
	reg [1:0] state_rx = RX_STATE_START;

	always @(posedge clk)
	begin
		if (read_clear)
		begin
			sample <= 0;
			index_rx <= 0;
			scratch <= 0;
		end
		else
		begin
			if (rx_clk_en)
			begin
				case (state_rx)
					RX_STATE_START:
					begin
						// Start counting from the first low sample,
						// once we've sampled a full bit, start collecting data bits.
						if (!rx || sample != 0)
						begin
							sample <= sample + 1;
						end

						if (sample == OVER_SAMPLES - 1)
						begin
							state_rx <= RX_STATE_DATA;
							index_rx <= 0;
							sample <= 0;
							scratch <= 0;
						end
					end

					RX_STATE_DATA:
					begin
						sample <= sample + 1;
						if (sample == OVER_SAMPLES / 2)
						begin
							scratch[index_rx[2:0]] <= rx;
							index_rx <= index_rx + 1;
						end
						if (index_rx == OVER_SAMPLES / 2 && sample == OVER_SAMPLES - 1)
						begin
							state_rx <= RX_STATE_STOP;
						end
					end

					RX_STATE_STOP:
					begin
						// Our baud clock may not be running at exactly the same rate as the transmitter.
						// If we thing that we're at least half way into the stop bit,
						// allow transition into handling the next start bit.
						if (sample == OVER_SAMPLES - 1 || (sample >= OVER_SAMPLES / 2 && !rx))
						begin
							data <= scratch;
							sample <= 0;
							state_rx <= RX_STATE_FINISHED;
						end
						else
						begin
							sample <= sample + 1;
						end
					end

					RX_STATE_FINISHED:
					begin
						// This state is to make sure that writing job has finished.
						state_rx <= RX_STATE_START;
					end

					default:
					begin
						state_rx <= RX_STATE_START;
					end
				endcase
			end
		end
	end
endmodule
