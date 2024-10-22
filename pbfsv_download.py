from azure.storage.blob import BlobServiceClient
import concurrent.futures
import pandas as pd
import os
from datetime import datetime, timezone
import csv
from moviepy.editor import VideoFileClip

def download_blob(blob_service_client, container_name, blob_name, local_path):
    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)
    with open(local_path, "wb") as f:
        f.write(blob_client.download_blob().readall())
    
def get_video_duration(file_path):
    try:
        with VideoFileClip(file_path) as clip:
            duration = int(clip.duration)
            hours = duration // 3600
            minutes = (duration % 3600) // 60
            return f"{hours:02d}:{minutes:02d}"
    except Exception as e:
        print(f"Error processing video file: {file_path}. Error: {e}")
        return "00:00"

def process_deviceid_folder(blob_service_client, container_name, streamname, mapping_df, external_hard_drive_path, start_date, end_date):
    print(f"Processing {streamname}")

    # Retrieve mapping information for the current streamname
    device_mapping = mapping_df[mapping_df['streamname'] == streamname].iloc[0]

    # Create deviceid folder on the external hard drive based on mapping information
    device_folder = os.path.join(
        external_hard_drive_path,
        str(device_mapping['district']),
        str(device_mapping['acname']),
        str(device_mapping['location']),
        str(streamname)
    )
    os.makedirs(device_folder, exist_ok=True)

    # Get the container client
    container_client = blob_service_client.get_container_client(container_name)

    # List blobs in the specified folder
    blobs = container_client.list_blobs(name_starts_with=f"live-record/{streamname}/")

    for blob in blobs:
        try:
            # Check if the blob is an instance of BlobPrefix (virtual directory)
            if blob.name.endswith('/'):
                continue

            # Extract date and time from the blob name
            blob_datetime_str = os.path.basename(blob.name).replace('.flv', '')
            blob_datetime = datetime.strptime(blob_datetime_str, "%Y-%m-%d-%H-%M-%S")

            # Check if the blob's date is within the specified date range
            if start_date <= blob_datetime.date() <= end_date:
                date_folder = os.path.join(device_folder, blob_datetime.strftime("%Y-%m-%d"))
                os.makedirs(date_folder, exist_ok=True)

                local_path = os.path.join(date_folder, os.path.basename(blob.name))

                # Download the blob only if the file does not exist or if its size is different
                if not os.path.exists(local_path) or os.path.getsize(local_path) != blob.size:
                    download_blob(blob_service_client, container_name, blob.name, local_path)
                    print(f"Downloaded: {local_path}")
                else:
                    print(f"Skipped (File already exists): {local_path}")

        except Exception as e:
            print(f"Error processing blob: {blob.name}, Error: {e}")

    # After downloading all files for a specific stream, process and write to CSV
    # process_and_write_csv(device_folder, device_mapping, streamname)

    print(f"Completed {streamname}")

def process_and_write_csv(device_folder, device_mapping, streamname):
    # Get list of all dates present in the folder
    dates = [name for name in os.listdir(device_folder) if os.path.isdir(os.path.join(device_folder, name))]

    for date in dates:
        # Initialize dictionary to store file names, sizes (in MB), and durations for each date
        files_info = {}
        total_size_mb = 0
        total_duration_seconds = 0

        # Iterate over files in the device folder for the current date
        date_folder = os.path.join(device_folder, date)
        for root, dirs, files in os.walk(date_folder):
            for file in files:
                if file.endswith('.flv'):
                    file_path = os.path.join(root, file)

                    # Calculate video duration
                    video_duration = get_video_duration(file_path)
                    total_duration_seconds += int(video_duration.split(':')[0]) * 3600 + int(video_duration.split(':')[1]) * 60

                    # Get file size
                    file_size = os.path.getsize(file_path) / (1024 * 1024)
                    total_size_mb += file_size

                    # Add file information to files_info dictionary
                    files_info[file] = (file_size, video_duration)

        # Write file names, sizes (in MB), durations, and serial numbers to a CSV file for the current date folder
        csv_file_path = os.path.join(date_folder, f"{device_mapping['district']}_{device_mapping['acname']}_{device_mapping['location']}_{streamname}_{date}_info.csv")
        with open(csv_file_path, 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(['Serial No', 'File Name', 'Size (MB)', 'Duration (HH:MM)'])
            total_serial_no = 0
            for i, (file_name, info) in enumerate(files_info.items(), start=1):
                total_serial_no = i
                writer.writerow([i, file_name, info[0], info[1]])

            # Write total size (MB) and total duration (HH:MM) at the end of the CSV file
            total_duration_formatted = f"{total_duration_seconds // 3600:02d}:{(total_duration_seconds % 3600) // 60:02d}"
            writer.writerow(['Total', '', f'{total_size_mb:.2f} MB', total_duration_formatted])

def main():

    # print("This is sample script! Please Modify the Connection String and Container Name!")
    # Replace these values with your actual storage account connection string and container name
    connection_string = "BlobEndpoint=https://punjab2024.blob.core.windows.net/;QueueEndpoint=https://punjab2024.queue.core.windows.net/;FileEndpoint=https://punjab2024.file.core.windows.net/;TableEndpoint=https://punjab2024.table.core.windows.net/;SharedAccessSignature=sv=2022-11-02&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2024-07-21T14:01:43Z&st=2024-07-19T06:01:43Z&spr=https,http&sig=kvyQYWgdfi6lLjaOIxZL4p7%2BP680nF66FbNG5CeIBI8%3D"
    container_name = "punjab2024"

    # Replace 'external_hard_drive_path' with the actual path of your external hard drive
    external_hard_drive_path = input("Enter the path of your external hard drive: ")

    # Replace 'your_file.xlsx' with the actual file path for the mapping Excel sheet
    mapping_excel_file_path = input("Enter the path of your mapping Excel sheet: ")

    # Replace 'your_file.xlsx' with the actual file path for the deviceid Excel sheet
    deviceid_excel_file_path = input("Enter the path of your deviceid Excel sheet: ")

    start_date_input = input("Enter the start date (YYYY-MM-DD): ")
    start_date = datetime.strptime(start_date_input, "%Y-%m-%d").date()

    end_date_input = input("Enter the end date (YYYY-MM-DD): ")
    end_date = datetime.strptime(end_date_input, "%Y-%m-%d").date()

    # Read mapping Excel data into a DataFrame
    mapping_df = pd.read_excel(mapping_excel_file_path)
    # Set the cutoff date to 17 November 2023 in UTC
    cutoff_date = datetime(2024, 3, 31, tzinfo=timezone.utc)

    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures = []

        # Read deviceid Excel data into a DataFrame
        deviceid_df = pd.read_excel(deviceid_excel_file_path)

        # Iterate through 'deviceid' column in the DataFrame
        for streamname in deviceid_df['streamname']:
            future = executor.submit(process_deviceid_folder, BlobServiceClient.from_connection_string(connection_string), container_name, streamname, mapping_df, external_hard_drive_path, start_date, end_date)
            futures.append(future)

        # Wait for all futures to complete
        concurrent.futures.wait(futures)

if __name__ == "__main__":
    main()
