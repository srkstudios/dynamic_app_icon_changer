import os
import sys
from PIL import Image, ImageEnhance

def tint_image(image_path, color, output_path):
    print(f"Processing {image_path} -> {output_path}")
    try:
        img = Image.open(image_path).convert("RGBA")
        r, g, b, a = img.split()
        
        # solid color image of the same size
        if color == 'blue':
            solid_color = Image.new("RGBA", img.size, (0, 0, 255, 255))
        elif color == 'green':
            solid_color = Image.new("RGBA", img.size, (0, 255, 0, 255))
            
        # Composite using original alpha
        out = Image.composite(solid_color, img, a)
        out.save(output_path)
    except Exception as e:
        print(f"Error processing {image_path}: {e}")

res_dir = r"s:/p-frelance/flutter-plugin/dynamic_app_icon/example/android/app/src/main/res"

for folder in os.listdir(res_dir):
    if folder.startswith("mipmap-"):
        folder_path = os.path.join(res_dir, folder)
        icon_path = os.path.join(folder_path, "ic_launcher.png")
        if os.path.exists(icon_path):
            tint_image(icon_path, 'blue', os.path.join(folder_path, "ic_launcher_blue.png"))
            tint_image(icon_path, 'green', os.path.join(folder_path, "ic_launcher_green.png"))

print("Done generating icons")
