# JKK_ReaTools
---
## 1. 설치하기
JKK_ReaTools를 사용하기 위해서는 **ReaImGui**가 반드시 설치되어 있어야 합니다. 
> ReaImGui는 REAPER에서 현대적인 인터페이스(UI)를 만들 수 있게 해주는 확장 라이브러리로, 이 스크립트는 모든 UI를 ReaImGui 기반으로 구성하고 있기 때문에 필수 구성요소입니다.
1. **[ReaPack](https://reapack.com/)의 설치**
    ReaImGui는 [**ReaPack**](https://reapack.com/)이라는 Extension을 통해 설치하는 것이 가장 간단하고 안전합니다. 
    그러므로 먼저 [**ReaPack**](https://reapack.com/)을 설치해야 합니다. [**ReaPack**](https://reapack.com/)의 설치 가이드는 [해당 사이트](https://reapack.com/)를 참고해주십시오. 설치가 정상적으로 완료되었다면, 윈도우 상단 메뉴바에 **Extension → ReaPack**이라는 메뉴를 확인할 수 있습니다. 
    정상적으로 설치되었다면, 위의 메뉴를 확인할 수 있습니다.
2. **ReaImGui의 설치**
    1. REAPER 상단 메뉴에서 **Extensions → ReaPack → Browse Packages** 를 선택합니다.
    2. 검색창에 `ReaImGui`를 입력합니다. (만약 여기서 검색되지 않는다면, [**이 사이트**](https://github.com/cfillion/reaimgui)에서 안내하는 가이드를 따르십시오.)
    3. **ReaImGui / Extensions(Type)** 라는 패키지를 확인했다면, 해당 패키지를 **우클릭 → Install 선택**합니다.
    4. **우측 하단의 Apply 클릭**합니다.
    5. 설치가 완료되었다면, REAPER를 재시작하면 됩니다.
3. **ReaImGui이 정상적으로 설치되었는지 확인하기**
    1. REAPER의 Action List (단축키: ? ) 창을 엽니다.
    2. 검색창에 `ImGui` 입력한 후, 아래와 같은 액션 또는 스크립트가 보이면 정상 설치된 것입니다.    
      **ReaImGui: Demo.lua 라는 스크립트를 찾으세요!**
4. **Extensions → ReaPack → Manage repositories**로 간 뒤, **Import/export... → Import repositories**
    <img width="383" height="140" alt="Screenshot 2025-12-30 at 23 00 01" src="https://github.com/user-attachments/assets/3a56e62d-a18f-4477-aaa5-163f6f32048d" />
6. 창에 `https://github.com/junkikim-sound/JKK_ReaTools/raw/master/index.xml`를 입력하고 OK를 누릅니다.
    <img width="501" height="175" alt="Screenshot 2025-12-30 at 23 00 54" src="https://github.com/user-attachments/assets/534a8455-e648-4baa-a8a5-ee2f0eca660d" />
7. Install/update JKK_ReaTools를 통해 전체 설치하면 완료!
    <img width="866" height="491" alt="Screenshot 2025-12-30 at 23 01 31" src="https://github.com/user-attachments/assets/26031222-f960-49ad-b85d-98213a5cefc8" />
8. Actions에서 JKK_ReaTools를 찾아 실행할 수 있습니다.
    <img width="1056" height="274" alt="Screenshot 2025-12-30 at 23 02 19" src="https://github.com/user-attachments/assets/769e7a8f-d595-4e90-982b-84e48ce89f25" />

     
---

## 2. 소개하기
<img width="532" height="665" alt="Screenshot 2025-12-30 at 22 19 23" src="https://github.com/user-attachments/assets/6831407d-d907-4fcd-a0fc-b6a7cc23ec7a" />

### A. Item Tools
- **Items Batch Controller**

    ![01 item batch adjust](https://github.com/user-attachments/assets/3f7a902c-06e4-46b7-8208-ef4ee56d7006)
    - Adjust the volume, pitch and playrate of selected items
    - 선택된 아이템의 볼륨과 피치를 일괄 조절합니다
- **Group Stretcher**
  
    ![03 stretch](https://github.com/user-attachments/assets/d6b121a7-e00c-4964-b8ed-16d0bc378b5b)
    - Stretch the entire group of selected items by a specified ratio
    - 선택된 아이템 그룹 전체를 지정한 비율로 스트레치합니다
- **Random Arranger**
  
    ![04 random arranger](https://github.com/user-attachments/assets/c58f0d28-1391-48a4-a36d-ebc838150ac4)
- **Move Items to Edit Cursor**
    - Moves the selected items to edit cursor
    - 선택된 아이템을 편집 커서 위치로 이동합니다
- **Show FX Chain for Item Take**
    - Open the FX chain for the selected item take
    - 선택된 아이템 테이크의 FX 체인을 엽니다
- **Render Items to New Takes**
    - Render items to new takes
    - 아이템을 새로운 테이크로 렌더링합니다
- **Render Items to Stereo Stem**
    - Renders selected items to a stereo file on a new track
    - 선택된 아이템 전체를 새 트랙에 스테레오 파일로 렌더링합니다
- **Region Creator**
  
    ![05](https://github.com/user-attachments/assets/8666253c-ca91-4ee8-aa6a-e53d74a4bc9d)
    - Creates individual regions based on the bounds of each item
    - 각 아이템의 길이를 기준으로 개별 리전을 생성합니다 (Name_01, Name_02, …)
- **Change Items Color**
  
    ![02 color selector](https://github.com/user-attachments/assets/229aef56-e939-4d87-b220-0c599c3ec867)
    - Changes the color of selected items
    - 선택된 아이템의 색상을 변경합니다

### B. Track Tools
- **Tracks Batch Controller**
    - Adjusts the volume, Pan of selected tracks collectively
    - 선택된 트랙의 볼륨을 일괄로 조절합니다
- **Track Selector by Level**
    - Select tracks by folder depth
    - 폴더 깊이에 따라 트랙을 선택합니다 (0: All, 1: Top-level, 2+: Child tracks)
- **Track Rename**
    - Batch rename selected tracks using the entered text and add numbering
    - 입력한 텍스트로 선택된 트랙을 일괄 변경하고 번호를 추가합니다
- **Time Selection Creator**
    - Create a time selection based on track item bounds
    - 트랙 아이템의 범위를 기준으로 타임 셀렉션을 생성합니다
- **Regions Creator**
    - Create regions based on track item bounds (using name of tracks)
    - 트랙 아이템의 범위를 기준으로 리전을 생성합니다 (트랙 이름 사용)
- **Create Parallel FX Group**
    - Automatically creates a parallel FX setup (Dry + 3 Wet tracks) with Pre-FX sends
    - 병렬 FX 라우팅(Dry + 3 Wet)을 자동 생성하고 아이템 이동 및 Pre-FX 센드를 연결합니다
- **Follow Folder Name**
    - Sync track names with their parent folder and add numbering
    - 부모 폴더 트랙 이름을 기준으로 트랙 이름을 동기화하고 번호를 추가합니다
- **Remove Unused Tracks**
    - Delete empty or unused tracks in the project
    - 프로젝트 내 비어 있거나 사용되지 않는 트랙을 삭제합니다
- **Change Tracks Color**
    - Changes the color of selected tracks
    - 선택된 트랙의 색상을 변경합니다

### C. Timeline Tools
- **Regions Rename**

    ![06](https://github.com/user-attachments/assets/8dded0aa-8f90-4c6b-8e03-935a7235cb91)
    - Batch rename regions within the time selection and adds numbering
    - 타임 셀렉션 내 리전의 이름을 일괄 변경하고 번호를 추가합니다 (Name_01, Name_02, …)
- **Set Master Mix Matrix by Time Selection**
    - Enable Master Mix in Render Matrix for regions overlapping with time selection
    - 타임 셀렉션과 겹치는 리전의 Master Mix 렌더 체크를 켜고 나머지는 끕니다
- Delete Regions in Time Selection

    ![08](https://github.com/user-attachments/assets/47b9896b-5d28-47d0-8972-ab52377bc123)
    - Delete regions within the time selection area
    - 타임 셀렉션 영역에 포함된 리전을 삭제합니다
- Delete All Regions
    - Deletes all regions in the project
    - 프로젝트 내 모든 리전을 삭제합니다
- Change Regions Color

    ![07](https://github.com/user-attachments/assets/2e380263-c47c-4042-807f-b6f4f789a6e1)
    - Changes the color of regions within the Time Selection
    - 타임 셀렉션 내 리전의 색상을 변경합니다


