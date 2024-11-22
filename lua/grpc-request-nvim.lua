-- Main module for the plugin
local M = {}

-- Helper function to trim whitespace from a string
local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function parse_grpc_line(line)
  -- Check if the line starts with "grpc" and extract the URL
  local grpc_command = line:match("^%s*[gG][rR][pP][cC]%s+(.*)")
  if not grpc_command then
    return nil, "The line does not start with 'grpc'"
  end

  -- Remove the "grpcs://" prefix if it exists
  local url = grpc_command:gsub("^grpcs://", "")

  -- Separate the server URL and the service/method
  local server, method = url:match("([^/]+)/(.*)")
  if not server or not method then
    return nil, "Invalid format: Unable to parse server URL and service/method"
  end

  -- Return the parsed server and method
  return server .. " " .. method, nil
end

-- Parse the buffer starting from the line under the cursor
local function parse_grpc_request()
  local current_line = vim.api.nvim_get_current_line()
  local grpc_command, err = parse_grpc_line(current_line)
  if not grpc_command then
    print("Error: " .. err)
    return nil
  end

  -- Get the current buffer and line number
  local buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Extract headers and JSON payload
  local headers = {}
  local payload = nil
  local lines = vim.api.nvim_buf_get_lines(buf, cursor_line, -1, false)

  -- Parse subsequent lines for headers and payload
  local is_parsing_headers = true
  for _, line in ipairs(lines) do
    line = trim(line)
    if line == "" then
      is_parsing_headers = false
    elseif line:match("^#") then
      -- Stop parsing if a line starts with #
      break
    elseif is_parsing_headers then
      table.insert(headers, line)
    else
      -- Append to the payload
      payload = (payload or "") .. line
    end
  end

  return grpc_command, headers, payload
end

-- Helper function to build the grpcurl command
local function build_grpcurl_command(grpc_command, headers, payload)
  local command = "grpcurl"

  -- Add headers
  for _, header in ipairs(headers) do
    command = command .. string.format(' -H "%s"', header)
  end

  -- Add JSON payload directly to the command
  if payload and payload ~= "" then
    command = command .. string.format(" -d '%s'", payload)
  end

  -- Add the main gRPC command
  command = command .. " " .. grpc_command

  -- Print the constructed command in Neovim
  print("Constructed grpcurl command:\n" .. command)

  return command
end

local function execute_grpcurl(command)
  -- Use io.popen to capture both stdout and stderr
  local handle = io.popen(command .. " 2>&1") -- Redirect stderr to stdout
  if handle then
    local result = handle:read("*a")
    local success, _, exit_code = handle:close()

    -- Open a new buffer to display the result or error
    vim.cmd("new")
    local buffer = vim.api.nvim_get_current_buf()

		-- Set the buffer as scratch
		vim.bo[buffer].buftype = "nofile"
		vim.bo[buffer].swapfile = false
		vim.bo[buffer].bufhidden = "wipe" -- Delete the buffer when the window is closed

    if success then
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(result, "\n"))
    else
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
        "Error executing grpcurl command:",
        string.format("Exit code: %d", exit_code),
        "",
      })
      vim.api.nvim_buf_set_lines(buffer, 3, -1, false, vim.split(result, "\n"))
    end
  else
    print("Error: Unable to execute grpcurl command")
  end
end

-- Main function to handle the DoRequest command
function M.do_request()
  -- Parse the gRPC request
  local grpc_command, headers, payload = parse_grpc_request()
  if not grpc_command then
    return
  end

  -- Build the grpcurl command
  local command = build_grpcurl_command(grpc_command, headers, payload)
  if not command then
    return
  end

  -- Execute the grpcurl command
  execute_grpcurl(command)
end

-- Set up the command
function M.setup()
  vim.api.nvim_create_user_command("GRPCRequest", M.do_request, {})
end

return M
