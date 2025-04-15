import sys
import serial
from PyQt5.QtWidgets import QApplication, QWidget, QLabel, QVBoxLayout, QHBoxLayout
from PyQt5.QtGui import QPixmap, QPainter, QColor, QFont, QLinearGradient, QGradient
from PyQt5.QtCore import Qt, QTimer, QRectF

class TemperatureApp(QWidget):
    def __init__(self):
        super().__init__()
        self.initUI()  # Initialize the user interface
        try:
            self.serial_port = serial.Serial('COM4', 115200, timeout=1)  # Open serial port for data communication
        except serial.SerialException as e:
            print(f"Serial port error: {e}")
            self.serial_port = None  # Set serial port to None if there's an error
        self.timer = QTimer(self)  # Timer to periodically check for new data
        self.timer.timeout.connect(self.read_serial_data)  # Connect timer event to data reading method
        self.timer.start(500)  # 500ms interval for reading data

    def initUI(self):
        self.setWindowTitle('Temperature Monitor')  # Set window title
        self.setGeometry(100, 100, 400, 600)  # Set window size and position

        self.temp_label = QLabel('Temperature: -- °C', self)  # Label for displaying temperature
        self.temp_label.setAlignment(Qt.AlignCenter)  # Center the text
        self.temp_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #EEE;")  # Set label style

        self.thermometer_label = QLabel(self)  # Label for displaying the thermometer
        self.thermometer_label.setPixmap(QPixmap(150, 400))  # Set initial pixmap size for thermometer
        self.thermometer_label.setAlignment(Qt.AlignCenter)  # Center the thermometer image

        self.status_label = QLabel('Waiting for data...', self)  # Status label
        self.status_label.setAlignment(Qt.AlignCenter)  # Center the status text
        self.status_label.setStyleSheet("font-size: 14px; color: #AAA;")  # Set status label style

        layout = QVBoxLayout()  # Create vertical layout for UI components
        layout.addWidget(self.temp_label)  # Add temperature label
        layout.addWidget(self.thermometer_label)  # Add thermometer label
        layout.addWidget(self.status_label)  # Add status label
        self.setLayout(layout)  # Set the layout for the window
        self.setStyleSheet("background-color: #282828;")  # Set background color to dark

        self.update_thermometer(0)  # Initialize the thermometer with 0°C

    def read_serial_data(self):
        if self.serial_port and self.serial_port.in_waiting >= 2:  # Check if data is available
            try:
                raw_data = self.serial_port.read(2)  # Read 2 bytes of data
                received_value = (raw_data[0] << 8) | raw_data[1]  # Combine bytes into a 16-bit value
                temp_celsius = received_value * 0.125  # Convert to temperature in Celsius
                self.temp_label.setText(f'Temperature: {temp_celsius:.1f} °C')  # Update temperature label
                self.update_thermometer(temp_celsius)  # Update thermometer graphic
                self.status_label.setText('Data received.')  # Update status
            except Exception as e:
                print(f"Error reading serial data: {e}")
                self.status_label.setText('Serial read error.')  # Display error message in case of failure
        elif self.serial_port is None:
            self.status_label.setText('Serial port not available.')  # If no serial port, show error message
        elif self.serial_port and self.serial_port.in_waiting < 2:
            self.status_label.setText('Waiting for data...')  # Indicate waiting for data from the serial port

    def update_thermometer(self, temperature):
        pixmap = QPixmap(150, 400)  # Create a new pixmap for the thermometer
        pixmap.fill(QColor(35,35,35))  # Set the background color of the thermometer
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.Antialiasing)  # Enable anti-aliasing for smoother drawing

        # Draw the thermometer body
        painter.setPen(Qt.NoPen)  # No outline
        painter.setBrush(QColor(50, 50, 50))  # Darker color for the thermometer body
        painter.drawRoundedRect(40, 20, 70, 300, 20, 20)  # Draw the main body of the thermometer
        painter.drawEllipse(40, 300, 70, 70)  # Draw the bottom part of the thermometer

        # Temperature fill (color changes based on the temperature)
        fill_height = int(280 * (temperature / 50))  # Scale the fill height based on temperature (max 50°C)
        if temperature < 10:
            color = QColor(0, 0, 200)  # Dark blue for low temperatures
        elif temperature < 20:
            color = QColor(0, 200, 200)  # Cyan for moderate temperatures
        elif temperature < 30:
            color = QColor(200, 120, 0)  # Orange for higher temperatures
        else:
            color = QColor(200, 0, 0)  # Red for high temperatures

        # Create a gradient for the temperature fill
        gradient = QLinearGradient(0, 370 - fill_height, 0, 370)
        gradient.setColorAt(0, color.lighter(120))  # Lighter version of the color for top part of the fill
        gradient.setColorAt(1, color)  # Base color for the fill
        painter.setBrush(gradient)
        painter.drawRoundedRect(45, 370 - fill_height, 60, fill_height, 15, 15)  # Draw the fill
        painter.drawEllipse(45, 300, 60, 60)  # Draw the rounded bottom of the thermometer

        # Draw temperature degree marks
        painter.setPen(QColor(150, 150, 150))  # Lighter color for degree marks
        for i in range(0, 51, 10):  # Draw degree marks every 10°C
            y = 300 - int(280 * (i / 50)) + 30  # Calculate y position based on the temperature scale
            painter.drawLine(30, y, 40, y)  # Draw the line for each degree mark
            painter.drawText(10, y + 5, f'{i}°C')  # Label the degree mark with the corresponding temperature

        painter.end()  # Finish drawing
        self.thermometer_label.setPixmap(pixmap)  # Set the updated pixmap to the thermometer label

if __name__ == '__main__':
    app = QApplication(sys.argv)
    ex = TemperatureApp()  # Create the application instance
    ex.show()  # Show the application window
    sys.exit(app.exec_())  # Run the event loop
