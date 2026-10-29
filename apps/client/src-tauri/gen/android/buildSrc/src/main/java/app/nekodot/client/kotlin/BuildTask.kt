import java.io.File
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.TaskAction
import javax.inject.Inject
import org.gradle.process.ExecOperations

abstract class BuildTask : DefaultTask() {
    @get:Inject abstract val execOperations: ExecOperations
    @Input var rootDirRel: String? = null
    @Input var projectDir: String? = null
    @Input var target: String? = null
    @Input var release: Boolean? = null

    @TaskAction fun assemble() {
        val source = File(projectDir, rootDirRel ?: throw GradleException("rootDirRel is required"))
        val cli = File(source, "../node_modules/@tauri-apps/cli/tauri.js").canonicalPath
        execOperations.exec {
            workingDir(source)
            executable(System.getenv("NEKODOT_NODE_BINARY") ?: "node")
            args(cli, "android", "android-studio-script", "--target", target ?: throw GradleException("target is required"))
            if (release == true) args("--release")
        }.assertNormalExitValue()
    }
}
