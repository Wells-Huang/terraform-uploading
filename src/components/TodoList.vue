<template>
  <div class="todo-container">
    <div class="todo-card">
      <h1 class="todo-title">📝 我的待辦清單</h1>
      
      <!-- 新增 TODO 表單 -->
      <div class="add-todo-section">
        <div class="input-group">
          <input
            v-model="newTodoText"
            @keyup.enter="addTodo"
            type="text"
            class="todo-input"
            placeholder="輸入新的待辦事項..."
            :disabled="loading || uploadingImage"
          />
          <div class="image-upload-wrapper">
            <input 
              type="file" 
              id="file-upload" 
              class="file-input" 
              accept="image/jpeg, image/png"
              @change="onFileSelected"
              :disabled="loading || uploadingImage"
            />
            <label for="file-upload" class="file-label" :class="{ 'has-file': selectedFile }">
              {{ selectedFile ? '🖼️ 已選圖片' : '📷 附圖' }}
            </label>
          </div>
        </div>
        
        <button @click="addTodo" class="add-button" :disabled="loading || uploadingImage || (!newTodoText.trim() && !selectedFile)">
          <span v-if="!adding && !uploadingImage">➕ 新增</span>
          <span v-else-if="uploadingImage">上傳圖...</span>
          <span v-else>⏳</span>
        </button>
      </div>
      
      <!-- 選取的圖片預覽與取消按鈕 -->
      <div v-if="selectedFile" class="image-preview-container">
        <span class="file-name">{{ selectedFile.name }} ({{ formatFileSize(selectedFile.size) }})</span>
        <button @click="clearSelectedFile" class="clear-file-btn" :disabled="uploadingImage">❌</button>
      </div>

      <!-- 載入狀態 -->
      <div v-if="loading && todos.length === 0" class="loading">
        <div class="spinner"></div>
        <p>載入中...</p>
      </div>

      <!-- 錯誤訊息 -->
      <div v-if="error" class="error-message">
        ⚠️ {{ error }}
      </div>

      <!-- TODO 列表 -->
      <div v-if="!loading || todos.length > 0" class="todo-list">
        <div v-if="todos.length === 0" class="empty-state">
          <p>🎉 目前沒有待辦事項！</p>
          <p class="empty-hint">新增一個開始吧</p>
        </div>

        <transition-group name="todo-list" tag="div">
          <div
            v-for="todo in todos"
            :key="todo.id"
            class="todo-item"
          >
            <div class="todo-content">
              <span class="todo-text">{{ todo.text }}</span>
              <div v-if="todo.imageUrl" class="todo-image-container">
                <img :src="todo.imageUrl" alt="Todo 圖片" class="todo-image" loading="lazy" />
              </div>
              <span class="todo-date">{{ formatDate(todo.createdAt) }}</span>
            </div>
            <button @click="deleteTodo(todo.id)" class="delete-button" :disabled="deleting === todo.id">
              <span v-if="deleting !== todo.id">🗑️</span>
              <span v-else>⏳</span>
            </button>
          </div>
        </transition-group>
      </div>

      <!-- API 連線狀態指示 -->
      <div class="api-status">
        <span class="status-dot" :class="{ 'connected': apiConnected }"></span>
        <span class="status-text">{{ apiConnected ? 'API 已連線' : 'API 未連線' }}</span>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'TodoList',
  data() {
    return {
      todos: [],
      newTodoText: '',
      loading: false,
      adding: false,
      deleting: null,
      error: null,
      apiConnected: false,
      apiBaseUrl: process.env.VUE_APP_API_BASE_URL || '',
      selectedFile: null,
      uploadingImage: false
    }
  },
  mounted() {
    this.fetchTodos()
  },
  methods: {
    async fetchTodos() {
      this.loading = true
      this.error = null

      try {
        const response = await fetch(`${this.apiBaseUrl}/api/todos`)
        
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }

        const data = await response.json()
        this.todos = data.todos || []
        this.apiConnected = true
      } catch (err) {
        console.error('Failed to fetch todos:', err)
        this.error = '無法載入待辦事項，請檢查網路連線'
        this.apiConnected = false
      } finally {
        this.loading = false
      }
    },

    onFileSelected(event) {
      const file = event.target.files[0]
      if (!file) return
      
      // Basic validation
      if (!['image/jpeg', 'image/png'].includes(file.type)) {
        this.error = '請上傳 JPEG 或 PNG 格式的圖片'
        return
      }
      if (file.size > 5 * 1024 * 1024) {
        this.error = '圖片大小不能超過 5MB'
        return
      }
      
      this.selectedFile = file
      this.error = null
    },

    clearSelectedFile() {
      this.selectedFile = null
      const fileInput = document.getElementById('file-upload')
      if (fileInput) fileInput.value = ''
    },

    formatFileSize(bytes) {
      if (bytes === 0) return '0 Bytes'
      const k = 1024
      const sizes = ['Bytes', 'KB', 'MB']
      const i = Math.floor(Math.log(bytes) / Math.log(k))
      return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
    },

    async uploadImage() {
      if (!this.selectedFile) return null
      
      try {
        this.uploadingImage = true
        
        // 1. 取得 Presigned URL
        const urlParams = new URLSearchParams({ contentType: this.selectedFile.type })
        const urlResponse = await fetch(`${this.apiBaseUrl}/api/upload-url?${urlParams.toString()}`)
        
        if (!urlResponse.ok) throw new Error('無法取得圖片上傳授權')
        const { uploadUrl, key } = await urlResponse.json()
        
        // 2. 將圖片直傳至 S3
        const uploadResponse = await fetch(uploadUrl, {
          method: 'PUT',
          headers: {
            'Content-Type': this.selectedFile.type
          },
          body: this.selectedFile
        })
        
        if (!uploadResponse.ok) throw new Error('圖片上傳失敗')
        
        // 3. 回傳將要從 processed 收取的 CDN 圖片路徑
        // key 是 raw/todo-images/<uuid>.jpg
        const processedKey = key.replace(/^raw\//, 'processed/')
        return `${this.apiBaseUrl}/${processedKey}`
        
      } catch (err) {
        console.error('Image upload error:', err)
        throw err
      } finally {
        this.uploadingImage = false
      }
    },

    async addTodo() {
      if (!this.newTodoText.trim() && !this.selectedFile) return

      this.adding = true
      this.error = null

      try {
        let imageUrl = null
        if (this.selectedFile) {
          try {
            imageUrl = await this.uploadImage()
          } catch (uploadErr) {
            this.error = uploadErr.message
            this.adding = false
            return
          }
        }

        const response = await fetch(`${this.apiBaseUrl}/api/todos`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ 
            text: this.newTodoText.trim() || '附加圖片',
            imageUrl: imageUrl 
          })
        })

        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }

        const data = await response.json()
        this.todos.push(data.todo)
        this.newTodoText = ''
        this.clearSelectedFile()
        this.apiConnected = true
      } catch (err) {
        console.error('Failed to add todo:', err)
        this.error = '無法新增待辦事項，請稍後再試'
        this.apiConnected = false
      } finally {
        this.adding = false
      }
    },

    async deleteTodo(id) {
      this.deleting = id
      this.error = null

      try {
        const response = await fetch(`${this.apiBaseUrl}/api/todos/${id}`, {
          method: 'DELETE'
        })

        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }

        this.todos = this.todos.filter(todo => todo.id !== id)
        this.apiConnected = true
      } catch (err) {
        console.error('Failed to delete todo:', err)
        this.error = '無法刪除待辦事項，請稍後再試'
        this.apiConnected = false
      } finally {
        this.deleting = null
      }
    },

    formatDate(dateString) {
      if (!dateString) return ''
      const date = new Date(dateString)
      return date.toLocaleString('zh-TW', {
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit'
      })
    }
  }
}
</script>

<style scoped>
.todo-container {
  min-height: 100vh;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  padding: 2rem;
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
}

.todo-card {
  max-width: 600px;
  margin: 0 auto;
  background: white;
  border-radius: 20px;
  padding: 2.5rem;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
}

.todo-title {
  font-size: 2rem;
  font-weight: 700;
  color: #333;
  margin-bottom: 2rem;
  text-align: center;
}

.add-todo-section {
  display: flex;
  gap: 0.75rem;
  margin-bottom: 2rem;
}

.todo-input {
  flex: 1;
  padding: 0.875rem 1.25rem;
  border: 2px solid #e0e0e0;
  border-radius: 12px;
  font-size: 1rem;
  transition: all 0.3s ease;
  outline: none;
}

.todo-input:focus {
  border-color: #667eea;
  box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
}

.add-button {
  padding: 0.875rem 1.5rem;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  border-radius: 12px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
}

.add-button:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 20px rgba(102, 126, 234, 0.4);
}

.add-button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.loading {
  text-align: center;
  padding: 3rem;
  color: #666;
}

.spinner {
  width: 50px;
  height: 50px;
  margin: 0 auto 1rem;
  border: 4px solid #f3f3f3;
  border-top: 4px solid #667eea;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

.error-message {
  background: #fee;
  color: #c33;
  padding: 1rem;
  border-radius: 8px;
  margin-bottom: 1rem;
  text-align: center;
}

.todo-list {
  margin-bottom: 1.5rem;
}

.empty-state {
  text-align: center;
  padding: 3rem 1rem;
  color: #999;
}

.empty-state p {
  margin: 0.5rem 0;
  font-size: 1.1rem;
}

.empty-hint {
  font-size: 0.9rem;
}

.todo-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1rem 1.25rem;
  background: #f8f9fa;
  border-radius: 12px;
  margin-bottom: 0.75rem;
  transition: all 0.3s ease;
}

.todo-item:hover {
  background: #e9ecef;
  transform: translateX(5px);
}

.todo-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.todo-text {
  font-size: 1rem;
  color: #333;
  font-weight: 500;
}

.todo-date {
  font-size: 0.75rem;
  color: #999;
}

.delete-button {
  padding: 0.5rem 0.75rem;
  background: #ff6b6b;
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 1.2rem;
  cursor: pointer;
  transition: all 0.3s ease;
}

.delete-button:hover:not(:disabled) {
  background: #ff5252;
  transform: scale(1.1);
}

.delete-button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.api-status {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding-top: 1rem;
  border-top: 1px solid #e0e0e0;
  font-size: 0.875rem;
  color: #666;
}

.status-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: #ff6b6b;
  transition: background 0.3s ease;
}

.status-dot.connected {
  background: #51cf66;
  box-shadow: 0 0 8px rgba(81, 207, 102, 0.6);
}

/* 動畫 */
.todo-list-enter-active, .todo-list-leave-active {
  transition: all 0.3s ease;
}

.todo-list-enter-from {
  opacity: 0;
  transform: translateX(-30px);
}

.todo-list-leave-to {
  opacity: 0;
  transform: translateX(30px);
}

/* 圖片上傳區域樣式 */
.input-group {
  display: flex;
  flex: 1;
  gap: 0.5rem;
}

.image-upload-wrapper {
  position: relative;
  display: flex;
  align-items: center;
}

.file-input {
  display: none;
}

.file-label {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0 1rem;
  height: 100%;
  background: white;
  border: 2px dashed #d1d5db;
  border-radius: 12px;
  color: #6b7280;
  font-size: 0.875rem;
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  transition: all 0.2s ease;
}

.file-label:hover {
  border-color: #667eea;
  color: #667eea;
  background: #f3f4f6;
}

.file-label.has-file {
  border-color: #51cf66;
  border-style: solid;
  color: #2b8a3e;
  background: #ebfbee;
}

.image-preview-container {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 1rem;
  background: #f8f9fa;
  border-radius: 8px;
  margin-bottom: 2rem;
  margin-top: -1rem;
  border: 1px solid #e9ecef;
}

.file-name {
  font-size: 0.875rem;
  color: #495057;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.clear-file-btn {
  background: none;
  border: none;
  cursor: pointer;
  font-size: 1rem;
  color: #adb5bd;
  transition: color 0.2s;
}

.clear-file-btn:hover:not(:disabled) {
  color: #fa5252;
}

.clear-file-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

/* 圖片顯示區 */
.todo-image-container {
  margin: 0.5rem 0;
  border-radius: 8px;
  overflow: hidden;
  max-width: 200px;
  border: 1px solid #e9ecef;
}

.todo-image {
  display: block;
  width: 100%;
  height: auto;
  object-fit: cover;
}
</style>
