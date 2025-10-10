<script setup lang="ts">
import StatusBar from './components/StatusBar.vue'
</script>

<template>
  <div class="p-6 space-y-4">
    <nav class="mb-4">
      <a href="/" class="mr-4">Home</a>
      <a href="/owner">Owner Panel</a>
    </nav>
    <StatusBar />
    <router-view />
  </div>
</template>

<style scoped></style>
