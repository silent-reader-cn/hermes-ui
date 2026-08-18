import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/projects/project_providers.dart';

void main() {
  group('ProjectsController 状态机', () {
    ProviderContainer makeContainer(_FakeProjectApi api) {
      final container = ProviderContainer(
        overrides: [
          projectApiFactoryProvider.overrideWithValue((_) => api),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('build：加载项目列表 → AsyncData', () async {
      final api = _FakeProjectApi(
        projects: [
          const ProjectSummary(projectId: 'p1', name: '项目一'),
          const ProjectSummary(projectId: 'p2', name: '项目二'),
        ],
      );
      final container = makeContainer(api);

      final state = await container.read(projectsProvider.future);
      expect(state.length, 2);
      expect(state.first.name, '项目一');
      expect(api.fetchCount, 1);
    });

    test('build：加载失败 → AsyncError；refresh 恢复', () async {
      final api = _FakeProjectApi(projects: []);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      // 初次 build 抛错 → future 拒绝
      await expectLater(
        container.read(projectsProvider.future),
        throwsA(isA<NetworkException>()),
      );

      api.fetchError = null;
      await container.read(projectsProvider.notifier).refresh();
      expect(container.read(projectsProvider).valueOrNull, isNotNull);
    });

    test('createProject：成功 → 追加列表并返回新项目（供 picker 选中）', () async {
      final api = _FakeProjectApi(projects: []);
      final container = makeContainer(api);
      await container.read(projectsProvider.future);

      final created = await container
          .read(projectsProvider.notifier)
          .createProject(name: '新项目');
      expect(created, isNotNull);
      expect(created!.name, '新项目');
      expect(container.read(projectsProvider).valueOrNull!.length, 1);
      expect(api.createCalls, ['新项目']);
    });

    test('createProject：空名 → 拒绝，不调 API', () async {
      final api = _FakeProjectApi(projects: []);
      final container = makeContainer(api);
      await container.read(projectsProvider.future);

      final created = await container
          .read(projectsProvider.notifier)
          .createProject(name: '   ');
      expect(created, isNull);
      expect(api.createCalls, isEmpty);
    });
  });
}

class _FakeProjectApi implements ProjectApi {
  _FakeProjectApi({this.projects = const []});

  List<ProjectSummary> projects;
  Object? fetchError;
  final List<String> createCalls = [];
  int fetchCount = 0;

  @override
  Future<ProjectsResponse> fetchProjects() async {
    fetchCount++;
    final error = fetchError;
    if (error != null) throw error;
    return ProjectsResponse(projects: projects);
  }

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async {
    createCalls.add(name);
    final project = ProjectSummary(
      projectId: 'p-${projects.length + 1}',
      name: name,
      color: color,
    );
    projects = [...projects, project];
    return ProjectMutationResponse(project: project);
  }

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async {
    return const ProjectMutationResponse();
  }

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async {
    return const ProjectMutationResponse();
  }
}