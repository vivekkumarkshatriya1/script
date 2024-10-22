from azure.storage.blob import BlobServiceClient
import concurrent.futures
import pandas as pd
import os
from datetime import datetime, timezone
from moviepy.editor import VideoFileClip

def download_blob(blob_service_client, container_name, blob_name, local_path):
    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)
    with open(local_path, "wb") as f:
        f.write(blob_client.download_blob().readall())
        

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

    print(f"Completed {streamname}")

def main():
    # Replace this value with your actual storage account connection string and container name
    connection_string = "BlobEndpoint=https://generall.blob.core.windows.net/;QueueEndpoint=https://generall.queue.core.windows.net/;FileEndpoint=https://generall.file.core.windows.net/;TableEndpoint=https://generall.table.core.windows.net/;SharedAccessSignature=sv=2022-11-02&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2024-11-20T17:49:07Z&st=2024-10-22T09:49:07Z&spr=https,http&sig=N2ptHgNfYcojCH0%2B3eJlrkjkemQHJVu57osxOHO19R4%3D"
    container_name = "generall"

    # Replace 'external_hard_drive_path' with the actual path of your external hard drive
    external_hard_drive_path = input("Enter the path of your external hard drive: ")

    # Replace 'your_file.xlsx' with the actual file path for the mapping Excel sheet
    excel_file_path = input("Enter the path of your Excel sheet: ")

    start_date_input = input("Enter the start date (YYYY-MM-DD): ")
    start_date = datetime.strptime(start_date_input, "%Y-%m-%d").date()

    end_date_input = input("Enter the end date (YYYY-MM-DD): ")
    end_date = datetime.strptime(end_date_input, "%Y-%m-%d").date()

    # Read Excel data into a DataFrame
    excel_df = pd.read_excel(excel_file_path)

    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures = []

        # Iterate through 'streamname' column in the DataFrame
        for streamname in excel_df['streamname']:
            future = executor.submit(process_deviceid_folder, BlobServiceClient.from_connection_string(connection_string), container_name, streamname, excel_df, external_hard_drive_path, start_date, end_date)
            futures.append(future)

        # Wait for all futures to complete
        concurrent.futures.wait(futures)

if __name__ == "__main__":
    main()
