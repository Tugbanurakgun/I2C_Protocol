clc;
clear;
close all;

% Serial port settings
serialPort = 'COM4';  % Enter your port here (change COM port if needed)
baudRate = 115200;  % Baud rate for communication
s = serial(serialPort, 'BaudRate', baudRate);  % Create serial object
fopen(s);  % Open the serial port for communication

% Data storage array
data = [];  % Initialize an empty array to store incoming data
numSamples = 500;  % Set the number of samples to collect for plotting

disp('Data acquisition started...');  % Display a message indicating data collection has started

while length(data) < numSamples  % Loop until the desired number of samples is collected
    if s.BytesAvailable >= 2  % Check if at least 2 bytes of data are available to read
        rawData = fread(s, 2, 'uint8');  % Read 2 bytes from the serial port as unsigned 8-bit integers
        receivedValue = bitshift(uint16(rawData(1)), 8) + uint16(rawData(2));  % Combine the two bytes to form a 16-bit value

        % Processing the received value (multiplying by 0.125 as a scaling factor)
        processedValue = double(receivedValue) * 0.125;  % Convert to double and apply scaling
        data = [data, processedValue];  % Append the processed value to the data array
        
        % Display received data in the console (hexadecimal, decimal, and processed temperature value)
        disp(['Received HEX: ', dec2hex(receivedValue, 4), ...
              ' -> Decimal: ', num2str(receivedValue), ...
              ' -> Temperature: ', num2str(processedValue)]);
        
        % Continuously update the plot with the new data
        plot(data, '-o', 'LineWidth', 1.5);  % Plot the data with circular markers
        grid on;  % Add grid to the plot
        xlabel('Sample Number');  % Label for the x-axis
        ylabel('Processed Value');  % Label for the y-axis
        title('UART 16-bit Data Graph');  % Title for the plot
        drawnow;  % Force MATLAB to update the plot
    end
end

disp('Data acquisition complete.');  % Indicate that data collection has finished

% Close the serial port and clean up
fclose(s);  % Close the serial port
delete(s);  % Delete the serial object
clear s;  % Clear the serial object from the workspace
