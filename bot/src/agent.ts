
// Import necessary classes and types from the Agents SDK
import { TurnState, MemoryStorage, TurnContext, AgentApplication, AttachmentDownloader }
  from '@microsoft/agents-hosting'
import { version } from '@microsoft/agents-hosting/package.json'
import { ActivityTypes } from '@microsoft/agents-activity'


// Define the shape of the conversation state
interface ConversationState {
  count: number;
}
// Alias for the application turn state
type ApplicationTurnState = TurnState<ConversationState>


// Create an attachment downloader for handling file attachments
const downloader = new AttachmentDownloader()

// Use in-memory storage for conversation state
const storage = new MemoryStorage()

// Create the main AgentApplication instance
export const agentApp = new AgentApplication<ApplicationTurnState>({
  storage,
  fileDownloaders: [downloader]
})


// Handler for the /reset command: clears the conversation state
agentApp.onMessage('/reset', async (context: TurnContext, state: ApplicationTurnState) => {
  state.deleteConversationState()
  await context.sendActivity('Ok I\'ve deleted the current conversation state.')
})


// Handler for the /count command: replies with the current message count
agentApp.onMessage('/count', async (context: TurnContext, state: ApplicationTurnState) => {
  const count = state.conversation.count ?? 0
  await context.sendActivity(`The count is ${count}`)
})


// Handler for the /diag command: sends the raw activity object for diagnostics
agentApp.onMessage('/diag', async (context: TurnContext, state: ApplicationTurnState) => {
  await state.load(context, storage)
  await context.sendActivity(JSON.stringify(context.activity))
})


// Handler for the /state command: sends the current state object
agentApp.onMessage('/state', async (context: TurnContext, state: ApplicationTurnState) => {
  await state.load(context, storage)
  await context.sendActivity(JSON.stringify(state))
})


// Handler for the /runtime command: sends Node.js and SDK version info
agentApp.onMessage('/runtime', async (context: TurnContext, state: ApplicationTurnState) => {
  const runtime = {
    nodeversion: process.version,
    sdkversion: version
  }
  await context.sendActivity(JSON.stringify(runtime))
})


// Welcome message when a new member is added to the conversation
agentApp.onConversationUpdate('membersAdded', async (context: TurnContext, state: ApplicationTurnState) => {
  await context.sendActivity('Hello from the Secure Bot Agent running Agents SDK version: ' + version)
})



// Generic message handler: increments count and echoes the user's message
agentApp.onActivity(ActivityTypes.Message, async (context: TurnContext, state: ApplicationTurnState) => {
  let count = state.conversation.count ?? 0
  state.conversation.count = ++count

  await context.sendActivity(`[${count}] you said: ${context.activity.text}`)
})


// Handler for activities whose type matches the regex /^message/
agentApp.onActivity(/^message/, async (context: TurnContext, state: ApplicationTurnState) => {
  await context.sendActivity(`Matched with regex: ${context.activity.type}`)
})


// Handler for activities where the type is exactly 'message', using a predicate function
agentApp.onActivity(
  async (context: TurnContext) => Promise.resolve(context.activity.type === 'message'),
  async (context, state) => {
    await context.sendActivity(`Matched function: ${context.activity.type}`)
  }
)