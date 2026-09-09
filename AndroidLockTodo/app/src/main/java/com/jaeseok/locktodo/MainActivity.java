package com.jaeseok.locktodo;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public final class MainActivity extends Activity {
    private static final String PREFS_NAME = "locktodo_android";
    private static final String TASKS_KEY = "tasks_json";
    private static final int OPEN_JSON_REQUEST = 7101;

    private final List<LockTodoTask> tasks = new ArrayList<>();
    private SharedPreferences preferences;
    private LinearLayout listContainer;
    private TextView statusText;
    private EditText quickAddField;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        configureSystemBars();

        preferences = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        loadTasks();
        importFromIntent(getIntent());
        render();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        importFromIntent(intent);
        render();
    }

    private void render() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(14), dp(18), dp(14));
        root.setBackgroundColor(Color.WHITE);

        TextView title = new TextView(this);
        title.setText("LockTodo");
        title.setTextColor(Color.rgb(18, 18, 20));
        title.setTextSize(30);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title);

        TextView subtitle = new TextView(this);
        subtitle.setText("Android에서 보는 무료 로컬 투두");
        subtitle.setTextColor(Color.rgb(118, 118, 128));
        subtitle.setTextSize(14);
        root.addView(subtitle);

        root.addView(summaryCard());
        root.addView(importBar());
        root.addView(quickAddBar());

        ScrollView scrollView = new ScrollView(this);
        listContainer = new LinearLayout(this);
        listContainer.setOrientation(LinearLayout.VERTICAL);
        scrollView.addView(listContainer);
        root.addView(scrollView, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
        ));

        setContentView(root);
        renderTasks();
    }

    private void configureSystemBars() {
        getWindow().setStatusBarColor(Color.WHITE);
        getWindow().setNavigationBarColor(Color.WHITE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            );
        }
    }

    private View summaryCard() {
        LinearLayout card = roundedCard();
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(12), dp(14), dp(12));

        int remaining = 0;
        int important = 0;
        for (LockTodoTask task : tasks) {
            if (!task.completed) remaining++;
            if (task.important) important++;
        }

        TextView headline = new TextView(this);
        headline.setText(remaining + "개 남음 · 중요 " + important + "개");
        headline.setTextSize(18);
        headline.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        headline.setTextColor(Color.rgb(22, 22, 24));
        card.addView(headline);

        statusText = new TextView(this);
        statusText.setText(tasks.isEmpty() ? "iPhone에서 내보낸 JSON 파일을 열어 가져오세요." : "로컬 저장됨");
        statusText.setTextSize(12);
        statusText.setTextColor(Color.rgb(118, 118, 128));
        card.addView(statusText);

        TextView hint = new TextView(this);
        hint.setText("iOS 설정 > Android 공유 > Android용 할 일 파일 만들기");
        hint.setTextSize(12);
        hint.setTextColor(Color.rgb(52, 120, 246));
        hint.setPadding(0, dp(8), 0, 0);
        card.addView(hint);

        return card;
    }

    private View importBar() {
        Button button = new Button(this);
        button.setText("iOS JSON 파일 가져오기");
        button.setTextSize(14);
        button.setAllCaps(false);
        button.setTextColor(Color.rgb(52, 120, 246));
        button.setBackground(roundedDrawable(Color.rgb(238, 243, 255), 14));
        button.setOnClickListener(v -> openJsonPicker());

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(46)
        );
        params.topMargin = dp(10);
        button.setLayoutParams(params);
        return button;
    }

    private View quickAddBar() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(8), 0, dp(8));

        quickAddField = new EditText(this);
        quickAddField.setHint("Android에서 새 할 일 추가");
        quickAddField.setSingleLine(true);
        quickAddField.setTextSize(14);
        quickAddField.setBackground(roundedDrawable(Color.rgb(246, 247, 250), 14));
        quickAddField.setPadding(dp(12), 0, dp(12), 0);
        row.addView(quickAddField, new LinearLayout.LayoutParams(0, dp(46), 1f));

        Button addButton = new Button(this);
        addButton.setText("+");
        addButton.setTextSize(20);
        addButton.setTextColor(Color.WHITE);
        addButton.setBackground(roundedDrawable(Color.rgb(52, 120, 246), 14));
        addButton.setOnClickListener(v -> addLocalTask());
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(dp(52), dp(46));
        buttonParams.leftMargin = dp(8);
        row.addView(addButton, buttonParams);

        return row;
    }

    private void renderTasks() {
        if (listContainer == null) return;
        listContainer.removeAllViews();

        if (tasks.isEmpty()) {
            TextView empty = new TextView(this);
            empty.setText("아직 할 일이 없습니다.");
            empty.setTextSize(15);
            empty.setTextColor(Color.rgb(118, 118, 128));
            empty.setGravity(Gravity.CENTER);
            empty.setPadding(0, dp(48), 0, dp(48));
            listContainer.addView(empty);
            return;
        }

        for (LockTodoTask task : tasks) {
            listContainer.addView(taskRow(task));
        }
    }

    private View taskRow(LockTodoTask task) {
        LinearLayout card = roundedCard();
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(dp(12), dp(10), dp(12), dp(10));

        CheckBox checkBox = new CheckBox(this);
        checkBox.setChecked(task.completed);
        checkBox.setOnCheckedChangeListener((buttonView, isChecked) -> {
            task.completed = isChecked;
            saveTasks();
            render();
        });
        card.addView(checkBox);

        LinearLayout textStack = new LinearLayout(this);
        textStack.setOrientation(LinearLayout.VERTICAL);
        textStack.setPadding(dp(8), 0, 0, 0);

        TextView title = new TextView(this);
        title.setText((task.important ? "★ " : "") + task.title);
        title.setTextSize(16);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(task.completed ? Color.rgb(142, 142, 147) : Color.rgb(18, 18, 20));
        textStack.addView(title);

        String meta = task.metaText();
        if (!meta.isEmpty()) {
            TextView detail = new TextView(this);
            detail.setText(meta);
            detail.setTextSize(12);
            detail.setTextColor(Color.rgb(118, 118, 128));
            textStack.addView(detail);
        }

        card.addView(textStack, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        return card;
    }

    private void openJsonPicker() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");
        startActivityForResult(intent, OPEN_JSON_REQUEST);
    }

    private LinearLayout roundedCard() {
        LinearLayout layout = new LinearLayout(this);
        layout.setBackground(roundedDrawable(Color.rgb(246, 247, 250), 18));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
        );
        params.topMargin = dp(10);
        layout.setLayoutParams(params);
        return layout;
    }

    private GradientDrawable roundedDrawable(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private void addLocalTask() {
        String title = quickAddField.getText().toString().trim();
        if (title.isEmpty()) return;
        tasks.add(0, new LockTodoTask(UUID.randomUUID().toString(), title, "", "today", false, false, "#3478F6", "", ""));
        quickAddField.setText("");
        saveTasks();
        render();
    }

    private void importFromIntent(Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        if (Intent.ACTION_SEND.equals(action)) {
            Uri streamUri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (streamUri != null) {
                importFromUri(streamUri);
            }
            return;
        }

        if (!Intent.ACTION_VIEW.equals(action) || intent.getData() == null) return;
        importFromUri(intent.getData());
    }

    private void importFromUri(Uri uri) {
        try {
            String json = readText(uri);
            JSONObject root = new JSONObject(json);
            JSONArray exportedTasks = root.optJSONArray("tasks");
            if (exportedTasks == null) return;

            tasks.clear();
            for (int index = 0; index < exportedTasks.length(); index++) {
                tasks.add(LockTodoTask.fromJson(exportedTasks.getJSONObject(index)));
            }
            saveTasks();
            if (statusText != null) {
                statusText.setText(tasks.size() + "개 가져옴");
            }
        } catch (Exception ignored) {
            if (statusText != null) {
                statusText.setText("가져오기 실패");
            }
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == OPEN_JSON_REQUEST && resultCode == RESULT_OK && data != null && data.getData() != null) {
            importFromUri(data.getData());
            render();
        }
    }

    private String readText(Uri uri) throws Exception {
        InputStream stream = getContentResolver().openInputStream(uri);
        if (stream == null) return "";

        StringBuilder builder = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line);
            }
        }
        return builder.toString();
    }

    private void loadTasks() {
        String raw = preferences.getString(TASKS_KEY, null);
        tasks.clear();

        if (raw == null) {
            tasks.add(new LockTodoTask(UUID.randomUUID().toString(), "iPhone에서 JSON 내보내기", "설정의 Android 공유 사용", "today", false, true, "#3478F6", "", ""));
            return;
        }

        try {
            JSONArray array = new JSONArray(raw);
            for (int index = 0; index < array.length(); index++) {
                tasks.add(LockTodoTask.fromJson(array.getJSONObject(index)));
            }
        } catch (Exception ignored) {
            tasks.clear();
        }
    }

    private void saveTasks() {
        JSONArray array = new JSONArray();
        for (LockTodoTask task : tasks) {
            array.put(task.toJson());
        }
        preferences.edit().putString(TASKS_KEY, array.toString()).apply();
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private static final class LockTodoTask {
        String id;
        String title;
        String notes;
        String category;
        boolean completed;
        boolean important;
        String colorHex;
        String dueDate;
        String locationTitle;

        LockTodoTask(String id, String title, String notes, String category, boolean completed, boolean important, String colorHex, String dueDate, String locationTitle) {
            this.id = id;
            this.title = title;
            this.notes = notes;
            this.category = category;
            this.completed = completed;
            this.important = important;
            this.colorHex = colorHex;
            this.dueDate = dueDate;
            this.locationTitle = locationTitle;
        }

        static LockTodoTask fromJson(JSONObject json) {
            return new LockTodoTask(
                    json.optString("id", UUID.randomUUID().toString()),
                    json.optString("title", "제목 없음"),
                    json.optString("notes", ""),
                    json.optString("category", "today"),
                    json.optBoolean("isCompleted", json.optBoolean("completed", false)),
                    json.optBoolean("isImportant", json.optBoolean("important", false)),
                    json.optString("colorHex", "#3478F6"),
                    json.optString("dueDate", ""),
                    json.optString("locationTitle", "")
            );
        }

        JSONObject toJson() {
            JSONObject json = new JSONObject();
            try {
                json.put("id", id);
                json.put("title", title);
                json.put("notes", notes);
                json.put("category", category);
                json.put("isCompleted", completed);
                json.put("isImportant", important);
                json.put("colorHex", colorHex);
                json.put("dueDate", dueDate);
                json.put("locationTitle", locationTitle);
            } catch (Exception ignored) {
            }
            return json;
        }

        String metaText() {
            List<String> parts = new ArrayList<>();
            if (!category.isEmpty()) parts.add(categoryTitle(category));
            if (!dueDate.isEmpty() && !"null".equals(dueDate)) parts.add(shortDate(dueDate));
            if (!locationTitle.isEmpty()) parts.add(locationTitle);
            if (!notes.isEmpty()) parts.add(notes);
            return String.join(" · ", parts);
        }

        private static String categoryTitle(String value) {
            if ("today".equals(value)) return "오늘";
            if ("tomorrow".equals(value)) return "내일";
            if ("later".equals(value)) return "나중에";
            if ("scheduled".equals(value)) return "예약됨";
            return value;
        }

        private static String shortDate(String value) {
            int split = value.indexOf('T');
            return split > 0 ? value.substring(0, split) : value;
        }
    }
}
