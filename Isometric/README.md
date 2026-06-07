# Isometric Roblox Prototype

## Camera

- Camera isometrica com rotacao em `Q` e `E`
- Transparencia de paredes e telhados quando o jogador entra em casas
- Camera aproxima dentro das casas e volta ao normal fora
- Recorte por andar: quando o personagem esta em um andar, andares acima somem

Tags recomendadas para casas:

- `Wall` nas paredes
- `Roof` nos telhados
- `Floor` nos pisos/lajes dos andares
- `Door` nas portas

Valores importantes em `IsometricCamera.client.lua`:

- `FLOOR_HEIGHT` altura media de cada andar
- `FLOOR_CUT_HEIGHT` altura visivel acima do pe do personagem dentro do andar atual
- `FLOOR_CUT_RADIUS` area ao redor do jogador onde andares acima podem sumir

## Sistema de porta

Arquivos:

- `src/ServerScriptService/DoorSystem.server.lua`
- `src/StarterPlayer/StarterPlayerScripts/DoorInteraction.client.lua`

## Como montar no Studio

### 1. RemoteEvent

Em `ReplicatedStorage`, crie:

- uma pasta chamada `DoorRemotes`
- dentro dela, um `RemoteEvent` chamado `DoorInteraction`

### 2. Script do servidor

Coloque `DoorSystem.server.lua` em:

- `ServerScriptService`

### 3. Script do cliente

Coloque `DoorInteraction.client.lua` em:

- `StarterPlayer > StarterPlayerScripts`

### 4. Preparar a porta

Para cada porta:

- use uma `Part` ou `Model`
- adicione a tag `Door`
- se for `Model`, defina `PrimaryPart`
- deixe a porta `Anchored = true`

Opcionalmente, configure atributos:

- `OpenAngle` numero, exemplo `90`
- `HingeSide` texto: `Left` ou `Right`
- `OpenDirection` texto: `Forward` ou `Backward`
- `CanOpen` bool, use `false` para uma porta que nunca abre
- `IsLocked` bool, use `true` para uma porta trancada que nao abre
- `IsOpen` bool

Opcionalmente, configure os sons no topo de `DoorSystem.server.lua`:

- `OPEN_SOUND_ID`
- `CLOSE_SOUND_ID`
- `LOCKED_SOUND_ID`

### 5. Montar a UI manualmente

Em `StarterGui`, crie:

- `ScreenGui` chamado `DoorUi`
- dentro dele, um `Frame` chamado `Frame`
- dentro do `Frame`, um `TextButton` chamado `OpenButton`
- opcionalmente, um `TextLabel` chamado `StatusLabel`

Estado inicial recomendado:

- `DoorUi.Enabled = false`
- `Frame.Visible = false`

## Sistema de loot

Arquivos:

- `src/ServerScriptService/LootSystem.server.lua`
- `src/StarterPlayer/StarterPlayerScripts/LootInteraction.client.lua`

Funciona em fases, estilo Project Zomboid: clica na caixa e aparece uma UI estilo porta com o botao Inspecionar; ao inspecionar, abrem os paineis da caixa e do inventario; ao clicar num item, abre uma telinha com acoes. Itens da caixa podem ser Transferidos para o inventario; itens do inventario podem ser Guardados (de volta na caixa), Equipados (viram Tool na hotbar) ou Dropados (caem no chao). O inventario tambem abre sozinho com Tab. Itens dropados no chao mostram um prompt com a tecla F ao passar o mouse, e podem ser pegos de volta.

### 1. RemoteEvent

Em `ReplicatedStorage`, crie:

- uma pasta chamada `LootRemotes`
- dentro dela, um `RemoteEvent` chamado `LootInteraction`

O segundo `RemoteEvent` (`InventoryRemote`), usado por equipar/dropar/pegar e pelo inventario do Tab, e criado automaticamente pelo servidor dentro de `LootRemotes` se nao existir. Voce pode cria-lo manualmente tambem, se preferir.

### 2. Script do servidor

Coloque `LootSystem.server.lua` em:

- `ServerScriptService`

### 3. Scripts do cliente

Coloque em `StarterPlayer > StarterPlayerScripts`:

- `LootInteraction.client.lua` (caixa + inventario + acoes)
- `DroppedItemPickup.client.lua` (prompt F para pegar itens dropados no chao)

### 4. Preparar o container

Para cada container:

- use uma `Part` ou `Model`
- adicione a tag `LootContainer`
- se for `Model`, defina `PrimaryPart`
- deixe o container `Anchored = true`

Opcionalmente, configure o atributo:

- `Title` texto, exemplo `Armario` (titulo mostrado na UI)

### 5. Definir os itens do container

Dentro do container (a `Part` ou o `Model`):

- crie uma `Folder` chamada `Loot`
- dentro dela, para cada item crie um `IntValue`
  - o `Name` do `IntValue` e o nome do item, exemplo `Bandagem`
  - o `Value` e a quantidade, exemplo `3`

Pegar um item diminui a quantidade em 1. Quando chega a zero, o `IntValue` e removido.

Opcionalmente, configure os sons no topo de `LootSystem.server.lua`:

- `OPEN_SOUND_ID`
- `CLOSE_SOUND_ID`
- `TAKE_SOUND_ID`

### 6. Montar a UI manualmente

A UI tem tres fases: (1) so o botao Inspecionar, (2) paineis da caixa + inventario, (3) telinha de acoes do item.

Em `StarterGui`, crie:

- `ScreenGui` chamado `LootUi`
- dentro dele, um `Frame` chamado `InspectFrame` (a UI inicial, estilo porta)
  - dentro dele, um `TextButton` chamado `InspectButton`
- um `Frame` chamado `LootFrame` (o nome antigo `Frame` ainda funciona) - painel da caixa
  - dentro dele, um `Frame` (ou `ScrollingFrame`) chamado `ItemList`
  - opcionalmente, um `TextLabel` chamado `TitleLabel`
  - opcionalmente, um `TextLabel` chamado `StatusLabel`
- um `Frame` chamado `InventoryFrame` - painel do inventario
  - dentro dele, um `Frame` (ou `ScrollingFrame`) chamado `ItemList`
  - opcionalmente, um `TextLabel` chamado `TitleLabel`
- um `Frame` chamado `ActionFrame` - a telinha de acoes do item
  - dentro dele, um `TextButton` chamado `TransferButton` (Transferir/Guardar - so com a caixa aberta)
  - dentro dele, um `TextButton` chamado `EquipButton` (equipa o item; vira Tool na hotbar)
  - dentro dele, um `TextButton` chamado `DropButton` (dropa o item no chao)
  - opcionalmente, um `TextLabel` chamado `ItemName` (mostra o item selecionado)

Importante sobre as fases: o `InspectFrame` precisa ser independente do `LootFrame` (nao coloque o `InspectFrame` dentro do `LootFrame`), porque eles aparecem em momentos diferentes. O `InventoryFrame` pode ficar dentro do `LootFrame` ou separado, pois aparece junto com ele.

Voce posiciona todos os paineis onde quiser no Studio; o sistema NAO move nada, ele apenas mostra e esconde nas posicoes que voce deixou. Os elementos sao encontrados em qualquer lugar dentro da `LootUi` (busca recursiva).

Os botoes de cada item sao criados automaticamente dentro de cada `ItemList`. Se voce quiser controlar a aparencia, coloque um `TextButton` chamado `ItemTemplate` dentro do `ItemList` (deixe `Visible = false`); ele sera clonado para cada item.

Estado inicial recomendado:

- `LootUi.Enabled = false`
- `InspectFrame.Visible = false`
- `LootFrame.Visible = false`
- `InventoryFrame.Visible = false`
- `ActionFrame.Visible = false`

### Fluxo e regras prontas do loot

- clicar na caixa abre o `InspectFrame` (so o botao Inspecionar), estilo porta
- clicar em `InspectButton` abre os paineis da caixa (`LootFrame`) e do inventario (`InventoryFrame`)
- clicar num item da caixa abre o `ActionFrame` (mostra so o botao Transferir)
- clicar num item do inventario abre o `ActionFrame` (mostra Guardar/Equipar/Dropar)
- `TransferButton` move TODA a quantidade do item da caixa para o inventario (so aparece com a caixa aberta)
- com um item do inventario e a caixa aberta, o mesmo botao vira "Guardar" e devolve tudo para a caixa
- `EquipButton` equipa o item: ele sai do inventario e vira uma `Tool` na hotbar do Roblox
- `DropButton` larga o item no chao, na frente do jogador, com a tag `DroppedItem`
- a telinha de acoes some sozinha se o item selecionado acabar na sua origem
- a UI fica onde voce posicionou; o sistema nao move os paineis
- clicar fora dos paineis, apertar `Escape` ou se afastar fecha a UI
- a caixa selecionada ganha um contorno fino
- nao usa `ClickDetector`
- o servidor valida tag e distancia antes de entregar itens
- o inventario do jogador fica guardado no servidor (em memoria, por sessao)
- limite de itens distintos no inventario controlado por `MAX_INVENTORY_SLOTS` no servidor
- sons opcionais tocam se os IDs forem configurados no script
- nada e criado automaticamente pelos scripts; a caixa, a `Folder Loot` e a UI precisam existir manualmente no Studio

### 7. Abrir o inventario com Tab

- aperte `Tab` para abrir/fechar apenas o `InventoryFrame` (sem caixa)
- nesse modo, clicar num item abre o `ActionFrame` com Equipar e Dropar (Transferir fica escondido, pois nao ha caixa)
- a tecla pode ser trocada em `INVENTORY_TOGGLE_KEY` no topo de `LootInteraction.client.lua`

### 8. Equipar e dropar (modelos dos itens)

Por padrao, equipar cria uma `Tool` generica e dropar cria uma `Part` generica. Para usar modelos personalizados, crie em `ReplicatedStorage` uma pasta chamada `ItemAssets`:

- `ItemAssets/Tools/<NomeDoItem>` - uma `Tool` (com `Handle`) clonada ao equipar aquele item
- `ItemAssets/WorldModels/<NomeDoItem>` - um `Model` (com `PrimaryPart`) ou `Part` clonado ao dropar aquele item

O nome do filho deve ser igual ao nome do item (o `Name` do `IntValue` na `Folder Loot`).

### 9. Pegar itens dropados (prompt F)

- itens dropados recebem a tag `DroppedItem` e vao para a pasta `DroppedItems` no `Workspace` (criada automaticamente)
- ao passar o mouse sobre um item dropado e estar perto, aparece o prompt que VOCE criou
- apertar `F` pega o item e devolve ao inventario
- o visual do prompt e MANUAL: crie um `BillboardGui` chamado `PickupPrompt` em `ReplicatedStorage`. O script apenas clona ele e o anexa ao item; nada e gerado automaticamente. Se nao existir, o prompt nao aparece (e um aviso e mostrado no Output)
- se tiver um `TextLabel` chamado `ItemLabel` dentro do `PickupPrompt`, o texto recebe o nome do item
- dica: na camera isometrica a camera fica longe, entao deixe o `MaxDistance` do `PickupPrompt` alto (ou 0 para ilimitado) e `AlwaysOnTop = true`
- distancia maxima ajustavel em `MAX_PICKUP_DISTANCE` (cliente e servidor)

## Regras prontas

- clicar na porta abre a UI na posicao do cursor
- botao `Abrir` vira `Fechar` quando a porta abre
- clicar no botao fecha a UI
- a porta selecionada ganha um contorno fino
- nao existe botao de trancar
- nao usa `ClickDetector`
- porta com `IsLocked = true` nao abre
- porta com `CanOpen = false` nao abre
- `OpenDirection` escolhe se a porta abre para frente ou para tras
- sons opcionais tocam se os IDs forem configurados no script
- nada e criado automaticamente pelos scripts; tudo precisa existir manualmente no Studio
#   P r o j e c t Z  
 