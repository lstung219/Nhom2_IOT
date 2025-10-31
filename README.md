# Hệ thống giám sát và điều khiển IoT

Dự án này là một giải pháp IoT toàn diện để giám sát và điều khiển dữ liệu môi trường bằng MQTT, dashboard web và ứng dụng di động.

## Tính năng

- **Giám sát dữ liệu thời gian thực:** Xem dữ liệu thời gian thực từ các cảm biến (nhiệt độ, độ ẩm, khí gas, ánh sáng) thông qua dashboard web và ứng dụng di động Flutter.
- **Điều khiển thiết bị:** Điều khiển từ xa các thiết bị như đèn và quạt.
- **Dữ liệu lịch sử:** Xem dữ liệu lịch sử với các khoảng thời gian khác nhau (1 giờ, 24 giờ, 7 ngày, 30 ngày).
- **Hệ thống cảnh báo:** Nhận cảnh báo khi giá trị cảm biến vượt qua ngưỡng được xác định trước.
- **Backend được Docker hóa:** Các dịch vụ backend (cơ sở dữ liệu PostgreSQL và dịch vụ dữ liệu) được đóng gói bằng Docker để dễ dàng cài đặt và triển khai.

## Kiến trúc

Hệ thống bao gồm các thành phần sau:

1.  **Firmware ESP32:** (Nằm trong `firmware_esp32c3`) - Vi điều khiển đọc dữ liệu cảm biến và gửi lên MQTT broker. Nó cũng đăng ký các chủ đề điều khiển để tác động đến các thiết bị.
2.  **MQTT Broker:** Một máy chủ MQTT trung tâm (ví dụ: HiveMQ) tạo điều kiện giao tiếp giữa ESP32, dịch vụ backend và các client.
3.  **Dịch vụ Backend:** (`iot_data_service.js`) - Một dịch vụ Node.js có chức năng:
    -   Đăng ký các chủ đề dữ liệu cảm biến trên MQTT broker.
    -   Lưu trữ dữ liệu trong cơ sở dữ liệu PostgreSQL.
    -   Cung cấp REST API cho dashboard web và ứng dụng di động để lấy dữ liệu lịch sử.
4.  **Dashboard Web:** (`dashboard.html`) - Giao diện dựa trên web để trực quan hóa dữ liệu thời gian thực, điều khiển thiết bị và xem dữ liệu lịch sử.
5.  **Ứng dụng di động Flutter:** (`app_flutter`) - Một ứng dụng di động đa nền tảng để giám sát và điều khiển hệ thống khi đang di chuyển.
6.  **Trình tạo dữ liệu:** (`generate_data.js`) - Một tập lệnh để mô phỏng dữ liệu cảm biến cho mục đích thử nghiệm.
7.  **Hệ thống cảnh báo:** (`alert_system.js`) - Một dịch vụ Node.js giám sát dữ liệu và gửi cảnh báo.

## Bắt đầu

### Điều kiện tiên quyết

-   [Node.js](https://nodejs.org/)
-   [Flutter](https://flutter.dev/)
-   [Docker](https://www.docker.com/) và [Docker Compose](https://docs.docker.com/compose/)

### Cài đặt Backend

1.  **Tạo tệp `.env`** trong thư mục gốc với nội dung sau:

    ```
    PGDATABASE=iot_db
    PGUSER=postgres
    PGPASSWORD=postgres
    ```

2.  **Khởi động các dịch vụ backend** bằng Docker Compose:

    ```bash
    docker-compose up -d
    ```

    Lệnh này sẽ khởi động cơ sở dữ liệu PostgreSQL và dịch vụ dữ liệu Node.js.

3.  **Chạy hệ thống cảnh báo** (tùy chọn):

    ```bash
    npm run alerts
    ```

### Cài đặt Frontend

#### Dashboard Web

Mở tệp `dashboard.html` trong trình duyệt web của bạn.

#### Ứng dụng di động Flutter

1.  **Điều hướng đến thư mục `app_flutter`:**

    ```bash
    cd app_flutter
    ```

2.  **Cài đặt các gói phụ thuộc:**

    ```bash
    flutter pub get
    ```

3.  **Chạy ứng dụng:**

    ```bash
    flutter run
    ```

## Sử dụng

-   **Dashboard Web:** Mở `dashboard.html` để xem dữ liệu thời gian thực và điều khiển thiết bị.
-   **Ứng dụng di động:** Sử dụng ứng dụng Flutter để giám sát và điều khiển hệ thống từ thiết bị di động của bạn.
-   **Mô phỏng dữ liệu:** Để tạo dữ liệu giả cho mục đích thử nghiệm, hãy chạy lệnh sau:

    ```bash
    npm start
    ```

## Cấu hình

-   **Backend:** Cấu hình backend nằm trong tệp `.env`.
-   **Dashboard Web:** URL và các chủ đề MQTT của broker có thể được cấu hình trong phần `<script>` của `dashboard.html`.
-   **Ứng dụng Flutter:** URL và các chủ đề MQTT của broker có thể được cấu hình trong tệp `lib/main.dart`.