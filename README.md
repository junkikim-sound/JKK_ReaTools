# JKK_ReaTools
**Reaper Toolkit for Game audio designer**

저는 게임 사운드 디자이너 **김준기(Junki Kim)**입니다. 
저는 전문 프로그래머가 아니라서 오류와 버그의 수정에 자신이 없습니다ㅜㅜ 그래도... 혹시라도 개선사항이 있다면 언제든지 저에게 메일을 보내주세요!

I am Junki Kim, a game sound designer. As I am not a professional programmer, I may not be perfect at fixing every error or bug, but I am always open to feedback! If you have any suggestions or improvements, please feel free to email me.

- Contact: junkikim.sound@gmail.com
---
## ⚙️ 1. Installation
ReaImGui must be installed to use JKK_ReaTools.
> ReaImGui is an essential library that allows for modern user interfaces within REAPER. Since this script's UI is entirely built on ReaImGui, it is a required component.
1. **Install [ReaPack](https://reapack.com/)**
   The easiest and safest way to install ReaImGui is through [**ReaPack**](https://reapack.com/). Please refer to [the ReaPack websit](https://reapack.com/) for the installation guide. Once installed, you will see an **Extensions → ReaPack** menu in REAPER's top menu bar.
2. **Install ReaImGui**
    1. Navigate to **Extensions → ReaPack → Browse Packages**.
    2. Search for `ReaImGui`. (If it doesn't appear, follow the guide at [**this site**](https://github.com/cfillion/reaimgui))
    3. Right-click the **ReaImGui / Extensions** package and select **Install**.
    4. Click **Apply** in the bottom right corner.
    5. Restart REAPER after the installation is complete.
3. Verify ReaImGui Installation
    1. Open REAPER’s Action List (Shortcut: `?`).
    2. Search for `ImGui`. If you see a script named **ReaImGui: Demo.lua**, the installation was successful.
4. Import JKK_Visualizer Repository
    1. Go to Extensions → ReaPack → Manage repositories.
        <img width="383" height="140" alt="Screenshot 2025-12-30 at 23 00 01" src="https://github.com/user-attachments/assets/3a56e62d-a18f-4477-aaa5-163f6f32048d" />
    2. Select Import/export... → Import repositories.
    3. Enter the following URL and click OK: `**https://github.com/junkikim-sound/JKK_ReaTools/raw/master/index.xml**`
        <img width="501" height="175" alt="Screenshot 2025-12-30 at 23 00 54" src="https://github.com/user-attachments/assets/534a8455-e648-4baa-a8a5-ee2f0eca660d" />
    4.  Find **JKK_ReaTools** in the package list, right-click to **install**, and click **Apply**.
        <img width="866" height="491" alt="Screenshot 2025-12-30 at 23 01 31" src="https://github.com/user-attachments/assets/26031222-f960-49ad-b85d-98213a5cefc8" />
    5. You can now find and run JKK_ReaTools in your Actions.
        <img width="1056" height="274" alt="Screenshot 2025-12-30 at 23 02 19" src="https://github.com/user-attachments/assets/769e7a8f-d595-4e90-982b-84e48ce89f25" />

     
---
## 🚀 2. Introduction
<img width="532" height="665" alt="Screenshot 2025-12-30 at 22 19 23" src="https://github.com/user-attachments/assets/6831407d-d907-4fcd-a0fc-b6a7cc23ec7a" />

### A. Item Tools
- **Items Batch Controller**: Adjust the volume, pitch and playrate of selected items
    ![01 item batch adjust](https://github.com/user-attachments/assets/3f7a902c-06e4-46b7-8208-ef4ee56d7006)
- **Group Stretcher**: Stretch the entire group of selected items by a specified ratio
    ![03 stretch](https://github.com/user-attachments/assets/d6b121a7-e00c-4964-b8ed-16d0bc378b5b)
- **Random Arranger**: 
    ![04 random arranger](https://github.com/user-attachments/assets/c58f0d28-1391-48a4-a36d-ebc838150ac4)
- **Move Items to Edit Cursor**: Moves the selected items to edit cursor
- **Show FX Chain for Item Take**: Open the FX chain for the selected item take
- **Render Items to New Takes**: Render items to new takes
- **Render Items to Stereo Stem**: Renders selected items to a stereo file on a new track
- **Region Creator**: Creates individual regions based on the bounds of each item (Name_01, Name_02, …)
    ![05](https://github.com/user-attachments/assets/8666253c-ca91-4ee8-aa6a-e53d74a4bc9d)
- **Change Items Color**: Changes the color of selected items
    ![02 color selector](https://github.com/user-attachments/assets/229aef56-e939-4d87-b220-0c599c3ec867)

### B. Track Tools
- **Tracks Batch Controller**: Adjusts the volume, Pan of selected tracks collectively
- **Track Selector by Level**: Select tracks by folder depth
- **Track Rename**: Batch rename selected tracks using the entered text and add numbering
- **Time Selection Creator**: Create a time selection based on track item bounds
- **Regions Creator**: Create regions based on track item bounds (using name of tracks)
- **Create Parallel FX Group**: Automatically creates a parallel FX setup (Dry + 3 Wet tracks) with Pre-FX sends
- **Follow Folder Name**: Sync track names with their parent folder and add numbering
- **Remove Unused Tracks**: Delete empty or unused tracks in the project
- **Change Tracks Color**: Changes the color of selected tracks

### C. Timeline Tools
- **Regions Rename**: Batch rename regions within the time selection and adds numbering (Name_01, Name_02, …)
    ![06](https://github.com/user-attachments/assets/8dded0aa-8f90-4c6b-8e03-935a7235cb91)
- **Set Master Mix Matrix by Time Selection**: Enable Master Mix in Render Matrix for regions overlapping with time selection
- **Delete Regions in Time Selection**: Delete regions within the time selection area
    ![08](https://github.com/user-attachments/assets/47b9896b-5d28-47d0-8972-ab52377bc123)
- **Delete All Regions**: Deletes all regions in the project
- **Change Regions Color**: Changes the color of regions within the Time Selection
    ![07](https://github.com/user-attachments/assets/2e380263-c47c-4042-807f-b6f4f789a6e1)

---
## 3. Technical Details
- Language: Lua 
- Library: REAPER v7.0+ / Dear ImGui 
- Engine: JSFX-to-Lua Data Streaming via gmem 
- Optimization: Optimized for low CPU usage even at a smooth 60FPS

---
## 🌊 About the Author
Junki Kim Game Sound Designer Specializing in game audio implementation and REAPER workflow optimization.

