import os
import shutil

from model.lofi2lofi_dataset import Lofi2LofiDataset
from model.lofi2lofi_model import Lofi2LofiModel
from model.train import train

if __name__ == '__main__':
    candidates = [
        "model/dataset/processed-spotify-all",
        "model/dataset/processed",
    ]
    dataset_folder = next((path for path in candidates if os.path.isdir(path)), None)
    if dataset_folder is None:
        raise FileNotFoundError(
            "No processed dataset folder found. Expected one of: " + ", ".join(candidates)
        )
    dataset_files = os.listdir(dataset_folder)
    if not dataset_files:
        raise FileNotFoundError(f"Dataset folder is empty: {dataset_folder}")

    max_epochs_env = os.environ.get("MAX_EPOCHS", "").strip()
    max_epochs = int(max_epochs_env) if max_epochs_env else None

    dataset = Lofi2LofiDataset(dataset_folder, dataset_files)
    model = Lofi2LofiModel()

    train(dataset, model, "lofi2lofi", max_epochs=max_epochs)

    decoder_candidates = [
        "lofi2lofi-decoder.pth",
        "lofi2lofi-decoder-epoch0.pth",
    ]
    decoder_target = "checkpoints/lofi2lofi_decoder.pth"
    decoder_source = next((path for path in decoder_candidates if os.path.isfile(path)), None)
    if decoder_source:
        os.makedirs("checkpoints", exist_ok=True)
        shutil.copyfile(decoder_source, decoder_target)
        print(f"Updated checkpoint: {decoder_target}")
